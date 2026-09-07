#!/usr/bin/env python3
"""Compare protected SMTP inputs with production and authenticate without mail.

Run locally on a protected GitHub runner. Candidate values travel to the existing
host only through SSH stdin. The remote program reads the running service's
injected environment; it neither writes configuration nor sends mail.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shlex
import smtplib
import ssl
import subprocess
import sys


SMTP_NAMES = ("SMTP_HOST", "SMTP_PORT", "SMTP_USER", "SMTP_PASSWORD")
SERVICE = "securewave-api.service"


def probe(candidate, running, smtp_factory=smtplib.SMTP):
    """Return only fixed status labels, booleans, and SMTP status codes."""
    result = {"email_sent": False, "configuration_changed": False}
    if not all(isinstance(candidate.get(k), str) and candidate[k] for k in SMTP_NAMES):
        return {**result, "status": "candidate_incomplete"}
    if not all(running.get(k) for k in SMTP_NAMES):
        return {**result, "status": "running_configuration_incomplete"}

    result["matches_running"] = {k: candidate[k] == running[k] for k in SMTP_NAMES}
    result["user_matches_running_sender"] = candidate["SMTP_USER"].casefold() == (
        running.get("FROM_EMAIL") or running.get("SMTP_FROM_EMAIL") or running["SMTP_USER"]
    ).casefold()
    if any(
        settings["SMTP_HOST"] != "smtp.gmail.com" or settings["SMTP_PORT"] != "587"
        for settings in (candidate, running)
    ):
        return {**result, "status": "provider_configuration_mismatch"}
    if all(result["matches_running"].values()):
        return {**result, "status": "same_as_running_not_retested"}
    if any("\x00" in candidate[k] for k in ("SMTP_USER", "SMTP_PASSWORD")):
        return {**result, "status": "invalid_candidate_encoding"}

    try:
        with smtp_factory("smtp.gmail.com", 587, timeout=15) as smtp:
            smtp.ehlo()
            smtp.starttls(context=ssl.create_default_context())
            smtp.ehlo()
            result["tls_verified"] = True
            if "PLAIN" not in smtp.esmtp_features.get("auth", "").upper().split():
                return {**result, "status": "plain_auth_unavailable"}
            code, _ = smtp.auth(
                "PLAIN",
                lambda challenge=None: "\0" + candidate["SMTP_USER"] + "\0" + candidate["SMTP_PASSWORD"],
            )
            return {
                **result,
                "status": "authentication_accepted" if code == 235 else "transport_or_protocol_failure",
                "smtp_code": code,
            }
    except smtplib.SMTPAuthenticationError as exc:
        # Server text can contain account details. Never return or log it.
        return {**result, "status": "authentication_rejected", "smtp_code": exc.smtp_code}
    except Exception:
        return {**result, "status": "transport_or_protocol_failure"}


def remote_main():
    try:
        candidate = json.load(sys.stdin)
        pid = subprocess.check_output(
            ["systemctl", "show", SERVICE, "--property=MainPID", "--value"],
            text=True, stderr=subprocess.DEVNULL, timeout=10,
        ).strip()
        if not re.fullmatch(r"[1-9][0-9]*", pid):
            raise ValueError("service has no process")
        running = dict(
            item.decode().split("=", 1)
            for item in Path("/proc", pid, "environ").read_bytes().split(b"\0")
            if b"=" in item
        )
        result = probe(candidate, running)
    except Exception:
        result = {"status": "remote_inspection_failed", "email_sent": False, "configuration_changed": False}
    print(json.dumps(result, sort_keys=True))


def runner_main():
    try:
        target_host = os.environ["SECUREWAVE_PRODUCTION_HOST"]
        target_user = os.environ["SECUREWAVE_PRODUCTION_USER"]
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*", target_host):
            raise ValueError("invalid host")
        if target_user != "securewave":
            raise ValueError("unexpected service account")
        candidate = {k: os.environ.get(k, "") for k in SMTP_NAMES}
        command = [
            "ssh", "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
            "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10",
            "-o", "UserKnownHostsFile=" + os.environ["SECUREWAVE_PRODUCTION_KNOWN_HOSTS_FILE"],
            "-i", os.environ["SECUREWAVE_PRODUCTION_SSH_KEY_FILE"],
            target_user + "@" + target_host,
            "python3 -c " + shlex.quote(Path(__file__).read_text()) + " --remote",
        ]
        completed = subprocess.run(
            command, input=json.dumps(candidate), text=True, capture_output=True, timeout=90,
        )
        if completed.returncode != 0:
            raise ValueError("remote execution failed")
        result = json.loads(completed.stdout)
        # This program emits no subprocess stderr, exceptions, environment, or
        # raw output. Even unexpected remote output is reduced to a fixed label.
        statuses = {
            "candidate_incomplete", "running_configuration_incomplete",
            "provider_configuration_mismatch", "same_as_running_not_retested",
            "invalid_candidate_encoding", "plain_auth_unavailable",
            "authentication_accepted", "authentication_rejected",
            "transport_or_protocol_failure", "remote_inspection_failed",
        }
        if result.get("status") not in statuses:
            raise ValueError("unexpected remote status")
        safe = {"status": result["status"], "email_sent": False, "configuration_changed": False}
        if "matches_running" in result:
            safe["matches_running"] = {k: result["matches_running"].get(k) is True for k in SMTP_NAMES}
        for key in ("tls_verified", "user_matches_running_sender"):
            if key in result:
                safe[key] = result[key] is True
        if type(result.get("smtp_code")) is int and 100 <= result["smtp_code"] <= 599:
            safe["smtp_code"] = result["smtp_code"]
        print(json.dumps(safe, sort_keys=True))
        return 0 if safe["status"] == "authentication_accepted" else 1
    except Exception:
        print(json.dumps({"status": "runner_or_ssh_failure", "email_sent": False, "configuration_changed": False}))
        return 1


if __name__ == "__main__":
    if sys.argv[1:] == ["--remote"]:
        remote_main()
    else:
        raise SystemExit(runner_main())

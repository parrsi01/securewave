#!/usr/bin/python3
"""Unprivileged replay of helper-owned checkpoints. Never uses an account JWT."""
import json
import socket
import time
import urllib.error
import urllib.request

SOCKET = "/run/securewave/helper.sock"
API = "https://api.securewaveapp.com/api"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise urllib.error.URLError("Reporting redirects are refused")


https_open = urllib.request.build_opener(NoRedirect()).open


def helper(operation, **arguments):
    body = "version=1\nop=" + operation + "\n"
    for key, value in arguments.items():
        body += key + "=" + str(value) + "\n"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(5)
        client.connect(SOCKET)
        client.sendall(body.encode())
        client.shutdown(socket.SHUT_WR)
        output = bytearray()
        while True:
            chunk = client.recv(4096)
            if not chunk:
                break
            output.extend(chunk)
            if len(output) > 65536:
                raise ValueError("Oversized helper response")
    values = {}
    for line in output.decode().splitlines():
        key, value = line.split("=", 1)
        # Pending JSON contains no escaped newlines; protocol escapes backslashes.
        values[key] = value.replace("\\n", "\n").replace("\\r", "\r").replace("\\\\", "\\")
    if values.get("ok") != "true":
        raise ValueError("Helper refused reporter operation")
    return values


def submit(record, opener=https_open):
    payload = {key: value for key, value in record.items() if key not in {"session_id", "token"}}
    request = urllib.request.Request(
        API + "/vpn/usage/sessions/" + str(record["session_id"]) + "/checkpoint",
        data=json.dumps(payload, separators=(",", ":")).encode(),
        headers={"Content-Type": "application/json", "Authorization": "UsageSession " + record["token"]},
        method="POST",
    )
    with opener(request, timeout=10) as response:
        data = json.loads(response.read(16384))
    if (data.get("session_id") != record["session_id"]
            or type(data.get("last_sequence")) is not int
            or data["last_sequence"] < record["sequence"]
            or data.get("bytes_sent", -1) < record["bytes_sent"]
            or data.get("bytes_received", -1) < record["bytes_received"]
            or (record["final"] and data.get("final_sequence") != record["sequence"])):
        raise ValueError("Server did not acknowledge the measured checkpoint")


def run():
    retry = {}
    while True:
        try:
            records = json.loads(helper("usage.pending")["records"])
            now = time.monotonic()
            for record in records:
                session = record["session_id"]
                next_time, failures, last_sequence = retry.get(session, (0, 0, 0))
                if now < next_time and (failures or not record["final"] or last_sequence == record["sequence"]):
                    continue
                try:
                    submit(record)
                    helper("usage.ack", session_id=session, sequence=record["sequence"])
                    retry[session] = (now + 10, 0, record["sequence"])
                except (OSError, ValueError, KeyError, TypeError) as error:
                    failures += 1
                    retry[session] = (now + min(60, 2 ** min(failures, 6)), failures, record["sequence"])
                    # Credentials, request bodies, URLs and exception text are never logged.
                    print("Usage recording awaiting acknowledgement (" + type(error).__name__ + ").", flush=True)
            pending_ids = {record["session_id"] for record in records}
            retry = {key: value for key, value in retry.items() if key in pending_ids}
        except (OSError, ValueError, KeyError, TypeError):
            pass
        time.sleep(2)


if __name__ == "__main__":
    run()

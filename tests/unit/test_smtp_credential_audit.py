"""Check the audit's no-mail, no-disclosure and bounded-auth guarantees."""

import importlib.util
import contextlib
import io
import json
from pathlib import Path
import smtplib
import unittest
from unittest.mock import MagicMock, patch


MODULE_PATH = Path(__file__).parents[2] / "scripts" / "audit_production_smtp.py"
SPEC = importlib.util.spec_from_file_location("smtp_audit", MODULE_PATH)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


class SmtpCredentialAuditTests(unittest.TestCase):
    def setUp(self):
        self.running = {
            "SMTP_HOST": "smtp.gmail.com", "SMTP_PORT": "587",
            "SMTP_USER": "fixture@example.invalid", "SMTP_PASSWORD": "fixture-old-password",
        }
        self.candidate = {**self.running, "SMTP_PASSWORD": "fixture-new-password"}
        self.factory = MagicMock()
        self.smtp = self.factory.return_value.__enter__.return_value
        self.smtp.esmtp_features = {"auth": "PLAIN LOGIN"}
        self.smtp.auth.return_value = (235, b"accepted")

    def assert_no_disclosure(self, result):
        encoded = json.dumps(result)
        for value in (self.candidate["SMTP_USER"], self.candidate["SMTP_PASSWORD"]):
            self.assertNotIn(value, encoded)

    def test_identical_pair_is_not_retried(self):
        result = audit.probe(self.running, self.running, self.factory)
        self.assertEqual(result["status"], "same_as_running_not_retested")
        self.factory.assert_not_called()

    def test_other_host_is_never_contacted(self):
        result = audit.probe({**self.candidate, "SMTP_HOST": "other.invalid"}, self.running, self.factory)
        self.assertEqual(result["status"], "provider_configuration_mismatch")
        self.factory.assert_not_called()

    def test_single_auth_uses_verified_tls_and_never_sends_mail(self):
        result = audit.probe(self.candidate, self.running, self.factory)
        self.assertEqual(result["status"], "authentication_accepted")
        self.assertTrue(result["tls_verified"])
        self.smtp.auth.assert_called_once()
        self.assertEqual(self.smtp.auth.call_args.args[0], "PLAIN")
        context = self.smtp.starttls.call_args.kwargs["context"]
        self.assertTrue(context.check_hostname)
        self.assertEqual(context.verify_mode, 2)
        self.smtp.sendmail.assert_not_called()
        self.smtp.send_message.assert_not_called()
        self.smtp.mail.assert_not_called()
        self.smtp.rcpt.assert_not_called()
        self.smtp.data.assert_not_called()
        self.assert_no_disclosure(result)

    def test_auth_error_response_cannot_disclose_credentials(self):
        self.smtp.auth.side_effect = smtplib.SMTPAuthenticationError(
            535, (self.candidate["SMTP_USER"] + self.candidate["SMTP_PASSWORD"]).encode(),
        )
        result = audit.probe(self.candidate, self.running, self.factory)
        self.assertEqual(result["status"], "authentication_rejected")
        self.assertEqual(result["smtp_code"], 535)
        self.smtp.auth.assert_called_once()
        self.assert_no_disclosure(result)

    def test_transport_exception_text_is_suppressed(self):
        self.factory.side_effect = RuntimeError(self.candidate["SMTP_PASSWORD"])
        result = audit.probe(self.candidate, self.running, self.factory)
        self.assertEqual(result["status"], "transport_or_protocol_failure")
        self.assert_no_disclosure(result)

    def test_runner_passes_candidate_via_stdin_and_suppresses_extra_output(self):
        env = {
            **self.candidate,
            "SECUREWAVE_PRODUCTION_HOST": "production.example.invalid",
            "SECUREWAVE_PRODUCTION_USER": "securewave",
            "SECUREWAVE_PRODUCTION_KNOWN_HOSTS_FILE": "/fixture/known_hosts",
            "SECUREWAVE_PRODUCTION_SSH_KEY_FILE": "/fixture/key",
        }
        remote = {
            "status": "authentication_rejected", "smtp_code": 535,
            "unexpected_secret": self.candidate["SMTP_PASSWORD"],
        }
        completed = MagicMock(returncode=0, stdout=json.dumps(remote), stderr=self.candidate["SMTP_PASSWORD"])
        output = io.StringIO()
        with patch.dict(audit.os.environ, env, clear=True), patch.object(
            audit.subprocess, "run", return_value=completed,
        ) as run, contextlib.redirect_stdout(output):
            self.assertEqual(audit.runner_main(), 1)
        self.assertNotIn(self.candidate["SMTP_PASSWORD"], repr(run.call_args.args))
        self.assertEqual(json.loads(run.call_args.kwargs["input"]), self.candidate)
        self.assertEqual(json.loads(output.getvalue())["status"], "authentication_rejected")
        self.assert_no_disclosure(json.loads(output.getvalue()))


if __name__ == "__main__":
    unittest.main()

from services.email_service import EmailService


def test_password_reset_email_contains_token_without_logging(monkeypatch):
    captured = {}

    def capture_send_email(_self, **kwargs):
        captured.update(kwargs)
        return True

    monkeypatch.setattr(EmailService, "send_email", capture_send_email)
    token = "reset-token-for-test"

    assert EmailService().send_password_reset_email(
        to_email="user@example.com",
        reset_token=token,
    )

    assert token in captured["html_content"]
    assert token in captured["text_content"]
    assert "Reset Token:" in captured["text_content"]

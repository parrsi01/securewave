from unittest.mock import patch

from services.auth_service import AuthService


def test_password_reset_stores_hashed_token_not_plaintext(db, test_user):
    service = AuthService(db)
    captured = {}

    def _capture_email(*, to_email, reset_token):
        captured["token"] = reset_token
        return True

    with patch.object(
        service.email_service,
        "send_password_reset_email",
        side_effect=_capture_email,
    ):
        result = service.request_password_reset(test_user.email)

    assert result is True
    db.refresh(test_user)
    raw_token = captured["token"]
    assert raw_token
    assert test_user.password_reset_token != raw_token
    assert test_user.password_reset_token == AuthService.hash_password_reset_token(raw_token)


def test_password_reset_confirm_accepts_valid_token(db, test_user):
    service = AuthService(db)
    captured = {}

    def _capture_email(*, to_email, reset_token):
        captured["token"] = reset_token
        return True

    with patch.object(
        service.email_service,
        "send_password_reset_email",
        side_effect=_capture_email,
    ):
        assert service.request_password_reset(test_user.email) is True

    token = captured["token"]
    success, error = service.reset_password(token, "ResetPass123!")
    assert success is True
    assert error is None


def test_password_reset_confirm_rejects_reused_token(db, test_user):
    service = AuthService(db)
    captured = {}

    def _capture_email(*, to_email, reset_token):
        captured["token"] = reset_token
        return True

    with patch.object(
        service.email_service,
        "send_password_reset_email",
        side_effect=_capture_email,
    ):
        assert service.request_password_reset(test_user.email) is True

    token = captured["token"]
    first_success, first_error = service.reset_password(token, "ResetPass123!")
    assert first_success is True
    assert first_error is None

    second_success, second_error = service.reset_password(token, "ResetPass456!")
    assert second_success is False
    assert second_error == "Invalid reset token"


def test_password_reset_confirm_rejects_tampered_token(db, test_user):
    service = AuthService(db)
    captured = {}

    def _capture_email(*, to_email, reset_token):
        captured["token"] = reset_token
        return True

    with patch.object(
        service.email_service,
        "send_password_reset_email",
        side_effect=_capture_email,
    ):
        assert service.request_password_reset(test_user.email) is True

    token = captured["token"]
    tampered = f"{token[:-1]}{'A' if token[-1] != 'A' else 'B'}"
    success, error = service.reset_password(tampered, "ResetPass123!")
    assert success is False
    assert error == "Invalid reset token"

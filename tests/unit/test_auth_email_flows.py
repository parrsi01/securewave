"""
Email verification and password reset flow tests.

These tests mock only the outbound mail transport. Tokens still move through
the same AuthService and API code paths used by production.
"""

from datetime import datetime, timedelta

from fastapi import status

from models.user import User
from services.hashing_service import hash_password, verify_password


class FakeEmailService:
    def __init__(self):
        self.verification_token = None
        self.verification_recipient = None
        self.reset_token = None
        self.reset_recipient = None

    def send_verification_email(self, to_email, verification_token, user_name=None):
        self.verification_recipient = to_email
        self.verification_token = verification_token
        return True

    def send_password_reset_email(self, to_email, reset_token, user_name=None):
        self.reset_recipient = to_email
        self.reset_token = reset_token
        return True


def _install_fake_email(monkeypatch):
    import services.auth_service as auth_module

    fake = FakeEmailService()
    monkeypatch.setattr(auth_module, "EmailService", lambda: fake)
    return auth_module, fake


def _create_user(db, email="flow@example.com", password="OldPass123!", verified=False):
    user = User(
        email=email,
        hashed_password=hash_password(password),
        email_verified=verified,
        is_active=True,
        subscription_status="basic",
        created_at=datetime.utcnow(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def test_verification_email_stores_hashed_token_and_consumes_once(db, monkeypatch):
    auth_module, fake_email = _install_fake_email(monkeypatch)
    user = _create_user(db)

    auth_service = auth_module.AuthService(db)
    assert auth_service.send_verification_email(user) is True
    db.refresh(user)

    raw_token = fake_email.verification_token
    assert raw_token
    assert fake_email.verification_recipient == "flow@example.com"
    assert user.email_verification_token != raw_token
    assert user.email_verification_token == auth_service._hash_token(raw_token)
    assert len(user.email_verification_token) == 64

    success, error = auth_service.verify_email(raw_token)
    assert success is True
    assert error is None
    db.refresh(user)
    assert user.email_verified is True
    assert user.email_verification_token is None
    assert user.email_verification_token_expires is None

    success, error = auth_service.verify_email(raw_token)
    assert success is False
    assert error == "Invalid verification token"


def test_expired_verification_token_is_rejected_and_cleared(db, monkeypatch):
    auth_module, _ = _install_fake_email(monkeypatch)
    auth_service = auth_module.AuthService(db)
    user = _create_user(db)
    raw_token = "expired-verification-token"
    user.email_verification_token = auth_service._hash_token(raw_token)
    user.email_verification_token_expires = datetime.utcnow() - timedelta(minutes=1)
    db.commit()

    success, error = auth_service.verify_email(raw_token)

    assert success is False
    assert error == "Verification token has expired"
    db.refresh(user)
    assert user.email_verified is False
    assert user.email_verification_token is None
    assert user.email_verification_token_expires is None


def test_password_reset_stores_hashed_token_resets_password_and_consumes_once(db, monkeypatch):
    auth_module, fake_email = _install_fake_email(monkeypatch)
    user = _create_user(db, verified=True)

    auth_service = auth_module.AuthService(db)
    assert auth_service.request_password_reset("FLOW@example.com") is True
    db.refresh(user)

    raw_token = fake_email.reset_token
    assert raw_token
    assert fake_email.reset_recipient == "flow@example.com"
    assert user.password_reset_token != raw_token
    assert user.password_reset_token == auth_service._hash_token(raw_token)
    assert len(user.password_reset_token) == 64

    success, error = auth_service.reset_password(raw_token, "NewPass123!")
    assert success is True
    assert error is None
    db.refresh(user)
    assert verify_password("NewPass123!", user.hashed_password) is True
    assert user.password_reset_token is None
    assert user.password_reset_token_expires is None
    assert user.password_reset_requested_at is None

    success, error = auth_service.reset_password(raw_token, "AnotherPass123!")
    assert success is False
    assert error == "Invalid reset token"


def test_expired_password_reset_token_is_rejected_and_cleared(db, monkeypatch):
    auth_module, _ = _install_fake_email(monkeypatch)
    auth_service = auth_module.AuthService(db)
    user = _create_user(db, verified=True)
    raw_token = "expired-reset-token"
    user.password_reset_token = auth_service._hash_token(raw_token)
    user.password_reset_token_expires = datetime.utcnow() - timedelta(minutes=1)
    user.password_reset_requested_at = datetime.utcnow() - timedelta(minutes=10)
    db.commit()

    success, error = auth_service.reset_password(raw_token, "NewPass123!")

    assert success is False
    assert error == "Reset token has expired"
    db.refresh(user)
    assert user.password_reset_token is None
    assert user.password_reset_token_expires is None
    assert user.password_reset_requested_at is None


def test_password_reset_request_for_missing_email_does_not_send_or_enumerate(db, monkeypatch):
    auth_module, fake_email = _install_fake_email(monkeypatch)
    auth_service = auth_module.AuthService(db)

    assert auth_service.request_password_reset("missing@example.com") is True

    assert fake_email.reset_token is None
    assert fake_email.reset_recipient is None


def test_register_and_verify_email_api_flow(client, db, monkeypatch):
    import routes.auth as auth_routes

    auth_module, fake_email = _install_fake_email(monkeypatch)
    monkeypatch.setattr(auth_routes, "DEMO_MODE", False)

    response = client.post("/api/auth/register", json={
        "email": "NewUser@Example.com",
        "password": "SecurePass123!",
        "password_confirm": "SecurePass123!",
    })

    assert response.status_code == status.HTTP_201_CREATED
    body = response.json()
    assert "access_token" not in body
    assert body["email"] == "newuser@example.com"
    assert body["email_sent"] is True

    user = db.query(User).filter(User.email == "newuser@example.com").first()
    assert user is not None
    assert user.email_verified is False
    assert user.email_verification_token == auth_module.AuthService(db)._hash_token(
        fake_email.verification_token
    )

    verify_response = client.post("/api/auth/verify-email", json={
        "token": fake_email.verification_token,
    })
    assert verify_response.status_code == status.HTTP_200_OK
    assert verify_response.json()["verified"] is True

    reuse_response = client.post("/api/auth/verify-email", json={
        "token": fake_email.verification_token,
    })
    assert reuse_response.status_code == status.HTTP_400_BAD_REQUEST


def test_password_reset_api_flow_is_enumeration_safe_and_single_use(client, db, test_user, monkeypatch):
    _, fake_email = _install_fake_email(monkeypatch)

    request_response = client.post("/api/auth/password-reset/request", json={
        "email": "TESTUSER@example.com",
    })
    assert request_response.status_code == status.HTTP_200_OK
    assert request_response.json() == {
        "message": "If the email exists, a password reset link has been sent"
    }
    assert fake_email.reset_token

    missing_response = client.post("/api/auth/password-reset/request", json={
        "email": "missing@example.com",
    })
    assert missing_response.status_code == status.HTTP_200_OK
    assert missing_response.json() == request_response.json()

    confirm_response = client.post("/api/auth/password-reset/confirm", json={
        "token": fake_email.reset_token,
        "new_password": "NewPass123!",
    })
    assert confirm_response.status_code == status.HTTP_200_OK
    assert confirm_response.json()["success"] is True

    db.refresh(test_user)
    assert verify_password("NewPass123!", test_user.hashed_password) is True

    reuse_response = client.post("/api/auth/password-reset/confirm", json={
        "token": fake_email.reset_token,
        "new_password": "AnotherPass123!",
    })
    assert reuse_response.status_code == status.HTTP_400_BAD_REQUEST

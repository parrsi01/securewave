from fastapi import status

from models.user import User
from services.hashing_service import hash_password
from services.jwt_service import create_access_token, create_refresh_token
from services.auth_service import AuthService


def _login(client, email: str = "testuser@example.com", password: str = "TestPass123"):
    response = client.post(
        "/api/auth/login",
        json={"email": email, "password": password},
    )
    assert response.status_code == status.HTTP_200_OK, response.text
    return response.json()


def test_admin_email_does_not_promote_user_on_login(client, db, test_user, monkeypatch):
    monkeypatch.setenv("ADMIN_EMAIL", test_user.email.upper())

    response = client.post(
        "/api/auth/login",
        json={"email": test_user.email.upper(), "password": "TestPass123"},
    )

    assert response.status_code == status.HTTP_200_OK
    db.refresh(test_user)
    assert test_user.is_admin is False


def test_inactive_user_cannot_login_refresh_or_use_existing_tokens(client, db, test_user):
    access_token = create_access_token(test_user)
    refresh_token = create_refresh_token(test_user)
    test_user.is_active = False
    db.commit()

    login = client.post(
        "/api/auth/login",
        json={"email": test_user.email, "password": "TestPass123"},
    )
    assert login.status_code == status.HTTP_401_UNAUTHORIZED

    me = client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert me.status_code == status.HTTP_401_UNAUTHORIZED

    refresh = client.post(
        "/api/auth/refresh",
        json={"refresh_token": refresh_token},
    )
    assert refresh.status_code == status.HTTP_401_UNAUTHORIZED

    session = client.get(
        "/api/auth/session",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert session.status_code == status.HTTP_200_OK
    assert session.json() == {"authenticated": False}


def test_logout_invalidates_access_and_refresh_tokens(client, db, test_user):
    tokens = _login(client)

    logout = client.post(
        "/api/auth/logout",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )

    assert logout.status_code == status.HTTP_200_OK
    assert logout.json() == {"status": "ok"}
    db.refresh(test_user)
    assert test_user.auth_token_version == 1

    me = client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert me.status_code == status.HTTP_401_UNAUTHORIZED

    refresh = client.post(
        "/api/auth/refresh",
        json={"refresh_token": tokens["refresh_token"]},
    )
    assert refresh.status_code == status.HTTP_401_UNAUTHORIZED


def test_logout_all_invalidates_access_and_refresh_tokens(client, db, test_user):
    tokens = _login(client)

    logout = client.post(
        "/api/auth/logout-all",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )

    assert logout.status_code == status.HTTP_200_OK
    assert logout.json() == {"status": "ok"}
    db.refresh(test_user)
    assert test_user.auth_token_version == 1

    me = client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert me.status_code == status.HTTP_401_UNAUTHORIZED

    refresh = client.post(
        "/api/auth/refresh",
        json={"refresh_token": tokens["refresh_token"]},
    )
    assert refresh.status_code == status.HTTP_401_UNAUTHORIZED


def test_password_change_invalidates_prior_tokens(client, test_user):
    tokens = _login(client)

    changed = client.post(
        "/api/auth/update-password",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
        json={
            "current_password": "TestPass123",
            "new_password": "ReplacementPass456",
        },
    )
    assert changed.status_code == status.HTTP_200_OK

    old_access = client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert old_access.status_code == status.HTTP_401_UNAUTHORIZED

    old_refresh = client.post(
        "/api/auth/refresh",
        json={"refresh_token": tokens["refresh_token"]},
    )
    assert old_refresh.status_code == status.HTTP_401_UNAUTHORIZED

    replacement = _login(client, password="ReplacementPass456")
    new_access = client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {replacement['access_token']}"},
    )
    assert new_access.status_code == status.HTTP_200_OK


def test_email_change_normalizes_and_returns_valid_replacement_tokens(client, db, test_user):
    tokens = _login(client)

    changed = client.post(
        "/api/auth/update-email",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
        json={"new_email": "Updated.User@EXAMPLE.COM", "password": "TestPass123"},
    )

    assert changed.status_code == status.HTTP_200_OK, changed.text
    replacement = changed.json()
    db.refresh(test_user)
    assert test_user.email == "updated.user@example.com"
    assert test_user.auth_token_version == 1

    old_access = client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert old_access.status_code == status.HTTP_401_UNAUTHORIZED

    old_refresh = client.post(
        "/api/auth/refresh",
        json={"refresh_token": tokens["refresh_token"]},
    )
    assert old_refresh.status_code == status.HTTP_401_UNAUTHORIZED

    new_access = client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {replacement['access_token']}"},
    )
    assert new_access.status_code == status.HTTP_200_OK
    assert new_access.json()["email"] == "updated.user@example.com"

    cookie_access = client.get("/api/auth/me")
    assert cookie_access.status_code == status.HTTP_200_OK
    assert cookie_access.json()["email"] == "updated.user@example.com"

    new_refresh = client.post(
        "/api/auth/refresh",
        json={"refresh_token": replacement["refresh_token"]},
    )
    assert new_refresh.status_code == status.HTTP_200_OK


def test_logout_is_isolated_to_current_account(client, db, test_user):
    other_user = User(
        email="other.user@example.com",
        hashed_password=hash_password("OtherPass123"),
        email_verified=True,
        is_active=True,
        is_admin=False,
    )
    db.add(other_user)
    db.commit()
    db.refresh(other_user)

    first_access = create_access_token(test_user)
    first_refresh = create_refresh_token(test_user)
    other_access = create_access_token(other_user)
    other_refresh = create_refresh_token(other_user)

    logout = client.post(
        "/api/auth/logout",
        headers={"Authorization": f"Bearer {first_access}"},
    )
    assert logout.status_code == status.HTTP_200_OK

    first_me = client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {first_access}"},
    )
    assert first_me.status_code == status.HTTP_401_UNAUTHORIZED
    first_refresh_response = client.post(
        "/api/auth/refresh",
        json={"refresh_token": first_refresh},
    )
    assert first_refresh_response.status_code == status.HTTP_401_UNAUTHORIZED

    other_me = client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {other_access}"},
    )
    assert other_me.status_code == status.HTTP_200_OK
    assert other_me.json()["id"] == other_user.id
    other_refresh_response = client.post(
        "/api/auth/refresh",
        json={"refresh_token": other_refresh},
    )
    assert other_refresh_response.status_code == status.HTTP_200_OK


def test_registration_and_login_normalize_email_case(client, db):
    registration = client.post(
        "/api/auth/register",
        json={
            "email": "Mixed.Case@EXAMPLE.COM",
            "password": "NormalizePass123",
            "password_confirm": "NormalizePass123",
        },
    )
    assert registration.status_code == status.HTTP_201_CREATED

    user = db.query(User).filter(User.email == "mixed.case@example.com").one()
    assert user.email == "mixed.case@example.com"

    login = client.post(
        "/api/auth/login",
        json={"email": "MIXED.CASE@EXAMPLE.COM", "password": "NormalizePass123"},
    )
    assert login.status_code == status.HTTP_200_OK


def test_unverified_account_cannot_sign_in(client, unverified_user):
    response = client.post(
        "/api/auth/login",
        json={"email": unverified_user.email, "password": "TestPass123"},
    )
    assert response.status_code == status.HTTP_403_FORBIDDEN


def test_one_time_tokens_are_hashed_and_password_reset_revokes_sessions(client, db, test_user):
    auth_service = AuthService(db)
    issued = {}

    auth_service.email_service.send_password_reset_email = lambda **kwargs: issued.update(kwargs) or True
    assert auth_service.request_password_reset(test_user.email) is True

    raw_token = issued["reset_token"]
    db.refresh(test_user)
    assert test_user.password_reset_token != raw_token
    assert len(test_user.password_reset_token) == 64

    old_access = create_access_token(test_user)
    old_refresh = create_refresh_token(test_user)
    success, error = auth_service.reset_password(raw_token, "ReplacementPass456")
    assert success is True, error

    assert client.get(
        "/api/auth/me", headers={"Authorization": f"Bearer {old_access}"}
    ).status_code == status.HTTP_401_UNAUTHORIZED
    assert client.post(
        "/api/auth/refresh", json={"refresh_token": old_refresh}
    ).status_code == status.HTTP_401_UNAUTHORIZED

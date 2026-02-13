
def test_revoked_access_token_is_rejected(client, test_user):
    login = client.post(
        "/api/auth/login",
        json={"email": test_user.email, "password": "TestPass123"},
    )
    assert login.status_code == 200, login.text
    access_token = login.json()["access_token"]

    revoke = client.post(
        "/api/auth/revoke-token",
        json={"token": access_token, "token_type": "access", "reason": "test"},
    )
    assert revoke.status_code == 200, revoke.text

    me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {access_token}"})
    assert me.status_code == 401


def test_revoked_refresh_token_cannot_refresh(client, test_user):
    login = client.post(
        "/api/auth/login",
        json={"email": test_user.email, "password": "TestPass123"},
    )
    assert login.status_code == 200, login.text
    refresh_token = login.json()["refresh_token"]

    revoke = client.post(
        "/api/auth/revoke-token",
        json={"token": refresh_token, "token_type": "refresh"},
    )
    assert revoke.status_code == 200, revoke.text

    refreshed = client.post("/api/auth/refresh", json={"refresh_token": refresh_token})
    assert refreshed.status_code == 401

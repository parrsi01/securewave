from models.auth_refresh_token import AuthRefreshToken


def test_refresh_token_rotation_marks_previous_session_revoked(client, test_user, db):
    login = client.post(
        "/api/auth/login",
        json={"email": test_user.email, "password": "TestPass123"},
    )
    assert login.status_code == 200, login.text
    body = login.json()
    old_refresh = body["refresh_token"]
    csrf = body["csrf_token"]

    sessions_before = db.query(AuthRefreshToken).filter(AuthRefreshToken.user_id == test_user.id).all()
    assert len(sessions_before) == 1
    assert sessions_before[0].revoked_at is None

    refreshed = client.post("/api/auth/refresh", headers={"X-CSRF-Token": csrf})
    assert refreshed.status_code == 200, refreshed.text
    new_refresh = refreshed.json()["refresh_token"]
    assert new_refresh != old_refresh

    sessions_after = db.query(AuthRefreshToken).filter(AuthRefreshToken.user_id == test_user.id).all()
    assert len(sessions_after) == 2
    revoked = [s for s in sessions_after if s.revoked_at is not None]
    active = [s for s in sessions_after if s.revoked_at is None]
    assert len(revoked) == 1
    assert len(active) == 1
    assert revoked[0].replaced_by_jti == active[0].token_jti

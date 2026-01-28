from fastapi import status


def test_login_sets_secure_cookies(client, test_user):
    response = client.post(
        "/api/auth/login",
        json={"email": "test@example.com", "password": "testpassword123"},
    )
    assert response.status_code == status.HTTP_200_OK
    set_cookies = response.headers.get_list("set-cookie")
    assert any("access_token=" in value and "HttpOnly" in value for value in set_cookies)
    assert any("refresh_token=" in value and "HttpOnly" in value for value in set_cookies)
    assert any("csrf_token=" in value and "HttpOnly" not in value for value in set_cookies)


def test_csrf_required_for_cookie_session(client, test_user):
    login = client.post(
        "/api/auth/login",
        json={"email": "test@example.com", "password": "testpassword123"},
    )
    assert login.status_code == status.HTTP_200_OK
    csrf_token = client.cookies.get("csrf_token")
    assert csrf_token

    no_csrf = client.post("/api/auth/logout")
    assert no_csrf.status_code == status.HTTP_403_FORBIDDEN

    with_csrf = client.post(
        "/api/auth/logout",
        headers={"X-CSRF-Token": csrf_token},
    )
    assert with_csrf.status_code == status.HTTP_200_OK

import routes.auth as auth_routes


def test_password_reset_throttle_keeps_generic_success_response(client):
    auth_routes._clear_password_reset_request_limits_for_tests()

    responses = [
        client.post(
            "/api/auth/password-reset/request",
            json={"email": f"nobody-{index}@example.com"},
        )
        for index in range(5)
    ]

    assert all(response.status_code == 200 for response in responses)
    assert {
        response.json()["message"]
        for response in responses
    } == {"If the email exists, a password reset link has been sent"}

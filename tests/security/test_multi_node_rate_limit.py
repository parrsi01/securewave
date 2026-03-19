from __future__ import annotations

import routes.auth as auth_routes
from main import app
from services.shared_security_state import (
    build_in_memory_security_state_backend,
    clear_shared_security_state_for_tests,
    set_shared_security_backend_for_tests,
)
from utils.inprocess_testclient import InProcessTestClient


def test_password_reset_throttle_is_shared_across_clients(client, db, monkeypatch):
    observed_emails: list[str] = []

    def fake_request_password_reset(self, email: str) -> bool:
        observed_emails.append(email)
        return True

    monkeypatch.setattr(auth_routes.AuthService, "request_password_reset", fake_request_password_reset)
    shared_backend = build_in_memory_security_state_backend()
    set_shared_security_backend_for_tests(shared_backend)
    clear_shared_security_state_for_tests()

    def _override_get_db():
        try:
            yield db
        finally:
            pass

    app.dependency_overrides[auth_routes.get_db] = _override_get_db
    headers = {"X-Forwarded-For": "203.0.113.10"}

    try:
        with InProcessTestClient(app, raise_server_exceptions=False) as client_a:
            with InProcessTestClient(app, raise_server_exceptions=False) as client_b:
                for index in range(3):
                    response = client_a.post(
                        "/api/auth/password-reset/request",
                        json={"email": f"user{index}@example.com"},
                        headers=headers,
                    )
                    assert response.status_code == 200

                response = client_b.post(
                    "/api/auth/password-reset/request",
                    json={"email": "overflow@example.com"},
                    headers=headers,
                )
                assert response.status_code == 200
                assert response.json()["message"] == "If the email exists, a password reset link has been sent"
    finally:
        app.dependency_overrides.pop(auth_routes.get_db, None)
        clear_shared_security_state_for_tests()
        set_shared_security_backend_for_tests(None)

    assert observed_emails == ["user0@example.com", "user1@example.com", "user2@example.com"]

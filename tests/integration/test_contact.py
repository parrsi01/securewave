def test_contact_returns_503_when_email_disabled(client):
    payload = {
        "name": "Test User",
        "email": "test@example.com",
        "subject": "Help",
        "message": "Please contact me about billing.",
    }
    response = client.post("/api/contact/submit", json=payload)
    assert response.status_code == 503

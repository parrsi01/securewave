def test_contact_accepts_when_email_disabled(client):
    payload = {
        "name": "Test User",
        "email": "test@example.com",
        "subject": "Help",
        "message": "Please contact me about billing.",
    }
    response = client.post("/api/contact/submit", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True

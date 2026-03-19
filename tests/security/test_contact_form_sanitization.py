import routers.contact as contact_router


def test_contact_form_escapes_html_in_email_templates(client, monkeypatch):
    sent_messages = []

    class FakeEmailService:
        enabled = True

        def send_email(self, **kwargs):
            sent_messages.append(kwargs)
            return True

    monkeypatch.setattr(contact_router, "EmailService", lambda: FakeEmailService())

    response = client.post(
        "/api/contact/submit",
        json={
            "name": "<b>Evil User</b>",
            "email": "attacker@example.com",
            "subject": "Security review request",
            "message": "<script>alert('xss')</script>\nNeed help now.",
        },
    )

    assert response.status_code == 200
    assert len(sent_messages) == 2

    for message in sent_messages:
        html = message["html_content"]
        assert "<script>" not in html
        assert "<b>Evil User</b>" not in html
        assert "&lt;script&gt;alert" in html
        assert "&lt;b&gt;Evil User&lt;/b&gt;" in html
        assert "<br>" in html


def test_contact_form_rejects_subject_header_injection(client):
    response = client.post(
        "/api/contact/submit",
        json={
            "name": "Header Tester",
            "email": "tester@example.com",
            "subject": "Hello\r\nBcc:evil@example.com",
            "message": "Checking subject validation for email safety.",
        },
    )

    assert response.status_code == 422

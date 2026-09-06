from unittest.mock import patch


def test_verification_page_route_and_privacy(client):
    response = client.get('/verify-email')
    assert response.status_code == 200
    assert response.headers['cache-control'] == 'no-store'
    assert response.headers['referrer-policy'] == 'no-referrer'
    assert '/js/verify-email.js' in response.text


def test_verification_email_keeps_token_out_of_http_url():
    from services import email_service

    with patch.object(email_service, 'APP_URL', 'https://securewaveapp.com/'), \
            patch.object(email_service.EmailService, 'send_email', return_value=True) as send:
        email_service.EmailService().send_verification_email('recipient@example.com', 'test-token')
    message = str(send.call_args)
    assert 'https://securewaveapp.com/verify-email#token=test-token' in message
    assert '/verify-email?token=' not in message


def test_verification_api_invalid_token_contract(client):
    response = client.post('/api/auth/verify-email', json={'token': 'nonexistent-test-token'})
    assert response.status_code == 400
    assert response.json()['error']['message'] == 'Invalid verification token'

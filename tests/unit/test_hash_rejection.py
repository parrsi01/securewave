from services.hashing_service import hash_password, verify_password


def test_unrecognized_stored_values_cannot_authenticate():
    for stored in (None, '', 'not-a-password-hash'):
        assert verify_password('not-a-password-hash', stored) is False


def test_valid_bcrypt_still_requires_correct_password():
    stored = hash_password('Regression-password-123!')
    assert verify_password('Regression-password-123!', stored) is True
    assert verify_password('Wrong-password-123!', stored) is False


def test_login_rejects_unrecognized_hash_without_issuing_tokens(client, db, test_user):
    test_user.hashed_password = 'not-a-password-hash'
    db.commit()
    response = client.post('/api/auth/login', json={
        'email': test_user.email, 'password': 'not-a-password-hash',
    })
    assert response.status_code == 401
    assert 'access_token' not in response.json()
    assert 'refresh_token' not in response.json()

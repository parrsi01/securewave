from scripts.email_live_proof import api_url, extract_token


def test_extract_token_accepts_raw_token():
    assert extract_token("abc123") == "abc123"


def test_extract_token_reads_verify_url_query_param():
    value = "https://securewave.app/verify-email?token=verify-token-123&x=1"
    assert extract_token(value) == "verify-token-123"


def test_extract_token_reads_reset_url_query_param():
    value = "https://securewave.app/reset-password?next=/login&token=reset-token-123"
    assert extract_token(value) == "reset-token-123"


def test_api_url_joins_base_and_path():
    assert api_url("https://api.securewaveapp.com/api/", "/auth/login") == (
        "https://api.securewaveapp.com/api/auth/login"
    )

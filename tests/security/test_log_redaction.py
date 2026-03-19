import logging

from main import RedactFilter


def _apply_filter(message: str) -> str:
    record = logging.LogRecord(
        name="securewave.test",
        level=logging.INFO,
        pathname=__file__,
        lineno=1,
        msg=message,
        args=(),
        exc_info=None,
    )
    RedactFilter().filter(record)
    return record.getMessage()


def test_redact_filter_redacts_bearer_tokens_and_wireguard_keys():
    token = "Bearer abcDEF.123-_XYZ"
    token2 = "bearer zzzYYY.456-_WWW"
    sk = "sk_test_fixture1"
    whsec = "whsec_fixture1"
    priv = "PrivateKey = xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    psk = "PresharedKey = yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy"
    msg = f"auth={token} auth2={token2} stripe={sk} webhook={whsec} cfg: {priv} {psk}"

    redacted = _apply_filter(msg)

    assert "abcDEF.123-_XYZ" not in redacted
    assert "zzzYYY.456-_WWW" not in redacted
    assert "sk_test_" not in redacted
    assert "whsec_" not in redacted
    assert "xxxxxxxxxxxxxxxx" not in redacted
    assert "yyyyyyyyyyyyyyyy" not in redacted
    assert "Bearer [redacted-token]" in redacted
    assert "bearer [redacted-token]" in redacted
    assert "[redacted-stripe-secret]" in redacted
    assert "[redacted-stripe-webhook-secret]" in redacted
    assert "PrivateKey = [redacted-wg-privatekey]" in redacted
    assert "PresharedKey = [redacted-wg-psk]" in redacted

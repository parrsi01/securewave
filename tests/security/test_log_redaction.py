import logging

from main import RedactFilter
from services.security_audit import EventCategory, EventType, SecurityAuditService


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
    priv = "PrivateKey = xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    psk = "PresharedKey = yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy"
    msg = f"auth={token} auth2={token2} cfg: {priv} {psk}"

    redacted = _apply_filter(msg)

    assert "abcDEF.123-_XYZ" not in redacted
    assert "zzzYYY.456-_WWW" not in redacted
    assert "xxxxxxxxxxxxxxxx" not in redacted
    assert "yyyyyyyyyyyyyyyy" not in redacted
    assert "Bearer [redacted]" in redacted
    assert "bearer [redacted]" in redacted
    assert "PrivateKey = [redacted-wg-privatekey]" in redacted
    assert "PresharedKey = [redacted-wg-psk]" in redacted


def test_redact_filter_redacts_password_refresh_and_pem_values():
    secret = "DoNotExposePassword123"
    refresh = "refresh-token-value-should-not-appear"
    pem = "-----BEGIN CERTIFICATE-----\nsecret certificate material\n-----END CERTIFICATE-----"

    redacted = _apply_filter(
        f"password={secret} refresh_token={refresh} certificate={pem}"
    )

    assert secret not in redacted
    assert refresh not in redacted
    assert "certificate material" not in redacted
    assert "[redacted]" in redacted


def test_security_audit_redacts_secrets_and_destinations(db):
    secret = "private-key-should-never-persist"
    destination = "https://traffic-destination.example/private"

    SecurityAuditService().log_event(
        event_type=EventType.VPN_CONFIG_GENERATED,
        event_category=EventCategory.SECURITY,
        action="issued",
        description=f"password={secret}",
        details={"private_key": secret, "endpoint": destination, "counter": 2},
    )

    from models.audit_log import AuditLog
    event = db.query(AuditLog).order_by(AuditLog.id.desc()).first()
    assert event is not None
    assert secret not in event.description
    assert event.details["private_key"] == "[redacted]"
    assert event.details["endpoint"] == "[redacted]"
    assert event.details["counter"] == 2


def test_database_diagnostics_do_not_expose_connection_target():
    from database.session import get_database_info

    info = get_database_info()

    assert info["url"] == "[redacted]"
    assert "password" not in str(info).lower()

from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from slowapi.util import get_remote_address

from main import RedactFilter
from utils.inprocess_testclient import InProcessTestClient


def test_redact_filter_masks_tokens_and_wireguard_secrets():
    record = type(
        "Record",
        (),
        {"getMessage": lambda self: "Bearer abc123 sk_test_abc123 whsec_def456 PrivateKey = secret PresharedKey = psk"},
    )()
    record.msg = record.getMessage()
    record.args = ()
    filtered = RedactFilter().filter(record)
    assert filtered is True
    assert "abc123" not in record.msg
    assert "sk_test_" not in record.msg
    assert "whsec_" not in record.msg
    assert "PrivateKey = secret" not in record.msg
    assert "PresharedKey = psk" not in record.msg
    assert "[redacted-token]" in record.msg


def test_env_example_has_no_default_password_literals():
    env_example = Path(".env.example.backend").read_text(encoding="utf-8")
    assignments = {}
    for raw in env_example.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        assignments[key.strip()] = value.strip().lower()

    risky_defaults = {"password123", "changeme123", "postgres", "postgres:postgres"}
    for key, value in assignments.items():
        if "PASSWORD" in key or key.endswith("_SECRET"):
            assert value not in risky_defaults


def test_rate_limiter_returns_429_after_limit():
    app = FastAPI()
    limiter = Limiter(key_func=get_remote_address, storage_uri="memory://", default_limits=["2/minute"])
    app.state.limiter = limiter
    app.add_middleware(SlowAPIMiddleware)

    @app.exception_handler(RateLimitExceeded)
    async def _rate_limit_handler(request: Request, exc: RateLimitExceeded):
        return JSONResponse({"detail": "rate_limited"}, status_code=429)

    @app.get("/limited")
    @limiter.limit("2/minute")
    async def limited(request: Request):
        return {"ok": True}

    with InProcessTestClient(app) as client:
        assert client.get("/limited").status_code == 200
        assert client.get("/limited").status_code == 200
        assert client.get("/limited").status_code == 429

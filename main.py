"""Small FastAPI entrypoint for the SecureWave Linux WireGuard beta."""

from __future__ import annotations

import contextvars
import json
import logging
import os
import re
import time
import uuid
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text

from database.session import SessionLocal
from models import user, vpn_server, wireguard_peer  # noqa: F401 - register active ORM tables
from routes import auth, vpn
from utils.sensitive_data import redact_text, sanitize_for_evidence

request_id_ctx = contextvars.ContextVar("request_id", default="-")


class _RedactFilter(logging.Filter):
    _email = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
    _token = re.compile(r"(Bearer\s+)[A-Za-z0-9._-]+", re.IGNORECASE)
    _private_key = re.compile(r"(PrivateKey\s*=\s*)[^\s]+")

    def filter(self, record: logging.LogRecord) -> bool:
        message = redact_text(record.getMessage())
        message = self._email.sub("[redacted-email]", message)
        message = self._token.sub(r"\1[redacted-token]", message)
        message = self._private_key.sub(r"\1[redacted-wg-privatekey]", message)
        record.msg = message
        record.args = ()
        record.request_id = request_id_ctx.get("-")
        return True


class _JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        return json.dumps(
            {
                "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(record.created)),
                "level": record.levelname,
                "logger": record.name,
                "request_id": getattr(record, "request_id", request_id_ctx.get("-")),
                "message": record.getMessage(),
            }
        )


_handler = logging.StreamHandler()
_handler.setFormatter(_JsonFormatter())
_handler.addFilter(_RedactFilter())
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO").upper(), handlers=[_handler])

app = FastAPI(
    title="SecureWave Linux Beta",
    version=os.getenv("APP_VERSION", "1.0.0-beta1"),
    docs_url="/api/docs" if os.getenv("ENVIRONMENT", "development") != "production" else None,
    redoc_url=None,
)
app.add_middleware(GZipMiddleware, minimum_size=500)

origins = [item.strip() for item in os.getenv("CORS_ORIGINS", "").split(",") if item.strip()]
if origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=False,
        allow_methods=["GET", "POST", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type"],
    )

allowed_hosts = [item.strip() for item in os.getenv("ALLOWED_HOSTS", "").split(",") if item.strip()]
if allowed_hosts:
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=allowed_hosts)


@app.middleware("http")
async def request_context(request: Request, call_next):
    supplied = request.headers.get("X-Request-ID", "")
    request_id = supplied if re.fullmatch(r"[A-Za-z0-9._-]{1,128}", supplied) else str(uuid.uuid4())
    token = request_id_ctx.set(request_id)
    try:
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        if os.getenv("ENVIRONMENT", "development") == "production":
            response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        return response
    finally:
        request_id_ctx.reset(token)


@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=422,
        content={
            "error": {
                "code": "validation_error",
                "message": "Request validation failed.",
                "details": sanitize_for_evidence(exc.errors()),
            },
            "request_id": request_id_ctx.get("-"),
        },
    )


@app.exception_handler(404)
async def not_found(request: Request, exc):
    if request.url.path.startswith("/api"):
        return JSONResponse(status_code=404, content={"error": {"code": "not_found", "message": "Not found."}})
    page = Path(__file__).resolve().parent / "static" / "404.html"
    return FileResponse(page, status_code=404) if page.exists() else JSONResponse({"detail": "Not found"}, status_code=404)


@app.get("/health")
@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "securewave-linux-beta"}


@app.get("/api/ready")
def ready():
    db = SessionLocal()
    try:
        db.execute(text("SELECT 1"))
        return {"status": "ready", "database": "connected"}
    except Exception:
        return JSONResponse(status_code=503, content={"status": "not_ready", "database": "unavailable"})
    finally:
        db.close()


@app.get("/version")
def version() -> dict[str, str]:
    return {
        "version": os.getenv("APP_VERSION", "1.0.0-beta1"),
        "commit": os.getenv("GIT_SHA", ""),
        "environment": os.getenv("ENVIRONMENT", "development"),
    }


app.include_router(auth.router)
app.include_router(vpn.router)

static_directory = Path(__file__).resolve().parent / "static"
for route, filename in {
    "/": "index.html",
    "/download": "download.html",
    "/terms.html": "terms.html",
    "/privacy.html": "privacy.html",
}.items():
    page = static_directory / filename

    async def page_handler(page=page):
        return FileResponse(page) if page.exists() else JSONResponse({"detail": "Not found"}, status_code=404)

    app.get(route, include_in_schema=False)(page_handler)

if static_directory.exists():
    app.mount("/static", StaticFiles(directory=str(static_directory)), name="static")
    # The same static tree backs the small public site and its candidate
    # download path when the API is run directly. Explicit API/page routes
    # above keep precedence over this fallback mount.
    app.mount("/", StaticFiles(directory=str(static_directory), html=True), name="site")

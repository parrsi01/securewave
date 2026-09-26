import os
import asyncio
import logging
import json
import re
import time
import uuid
import contextvars
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request, HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse
from fastapi.middleware.gzip import GZipMiddleware
from release_metadata import get_app_version
from sqlalchemy import text
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from database.session import SessionLocal
# Import all models for SQLAlchemy registration - needed for ORM
from models import (  # noqa: F401
    subscription,
    user,
    vpn_connection,
    vpn_server,
    vpn_usage_event,
    wireguard_peer,
)
from routes import auth as new_auth, user, vpn as new_vpn
from services.wireguard_service import WireGuardService
from utils.env_validation import validate_fernet_key, is_production
from utils.sensitive_data import redact_text, safe_validation_errors, sanitize_for_evidence

# Request ID context
request_id_ctx = contextvars.ContextVar("request_id", default="-")


class RedactFilter(logging.Filter):
    """Redact emails and obvious secrets from log messages."""
    _email_re = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
    _token_re = re.compile(r"(Bearer\s+)[A-Za-z0-9._\-]+", re.IGNORECASE)
    _wg_priv_re = re.compile(r"(PrivateKey\s*=\s*)([^\s]+)")
    _wg_psk_re = re.compile(r"(PresharedKey\s*=\s*)([^\s]+)")

    def filter(self, record: logging.LogRecord) -> bool:
        message = redact_text(record.getMessage())
        message = self._email_re.sub("[redacted-email]", message)
        message = self._token_re.sub(r"\1[redacted-token]", message)
        # Defensive: never emit WireGuard secrets if a config blob is accidentally logged.
        message = self._wg_priv_re.sub(r"\1[redacted-wg-privatekey]", message)
        message = self._wg_psk_re.sub(r"\1[redacted-wg-psk]", message)
        record.msg = message
        record.args = ()
        record.request_id = request_id_ctx.get("-")
        return True

class JsonFormatter(logging.Formatter):
    """Minimal JSON formatter for logs."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(record.created)),
            "level": record.levelname,
            "logger": record.name,
            "request_id": getattr(record, "request_id", request_id_ctx.get("-")),
            "message": record.getMessage(),
        }
        return json.dumps(payload)


LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
handler = logging.StreamHandler()
handler.setFormatter(JsonFormatter())
handler.addFilter(RedactFilter())
logging.basicConfig(level=LOG_LEVEL, handlers=[handler])

# Alembic remains the production schema path; local/dev startup also ensures
# tables exist so the Linux app can be exercised without the old bootstrap maze.

docs_enabled = os.getenv("ENVIRONMENT") != "production"


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context manager for startup and shutdown events"""
    logger = logging.getLogger(__name__)

    # Startup
    logger.info("FastAPI startup: Quick initialization only")

    # Create data directory if needed (fast operation)
    try:
        data_dir = Path(__file__).resolve().parent / "data"
        data_dir.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        logger.warning(f"Could not create data directory: {e}")

    require_encryption_keys(logger)
    require_production_config(logger)

    # Schedule background initialization to run after startup completes
    if os.getenv("TESTING", "").lower() != "true":
        asyncio.create_task(initialize_app_background())
    else:
        logger.info("Skipping background initialization in test mode")

    logger.info("FastAPI startup complete - background initialization scheduled")

    yield  # Application runs here

    logger.info("FastAPI shutdown initiated")


app = FastAPI(
    title="SecureWave VPN",
    version=get_app_version(),
    docs_url="/api/docs" if docs_enabled else None,
    redoc_url="/api/redoc" if docs_enabled else None,
    openapi_url="/api/openapi.json" if docs_enabled else None,
    lifespan=lifespan,
)

is_testing = os.getenv("TESTING", "").lower() == "true"
app.add_middleware(GZipMiddleware, minimum_size=500)

# Rate Limiting Configuration
limiter = Limiter(
    key_func=get_remote_address,
    storage_uri=os.getenv("REDIS_URL", "memory://"),
    default_limits=["200 per minute"]
)
app.state.limiter = limiter
if not is_testing:
    app.add_middleware(SlowAPIMiddleware)


@app.exception_handler(RateLimitExceeded)
async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    if request.url.path.startswith("/api"):
        return api_error("rate_limited", "Too many requests", status_code=429)
    return JSONResponse({"detail": "Too many requests"}, status_code=429)

# CORS Configuration - enable only when explicitly set
origins_env = os.getenv("CORS_ORIGINS", "")
if origins_env:
    origins = [o.strip() for o in origins_env.split(",") if o.strip()]

    # Security check: No wildcards in production
    if os.getenv("ENVIRONMENT") == "production" and "*" in origins:
        raise RuntimeError(
            "Production requires specific CORS_ORIGINS environment variable. "
            "Wildcards are not allowed in production."
        )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],  # Explicit methods
        allow_headers=["Authorization", "Content-Type", "X-CSRF-Token"],  # Explicit headers
        max_age=3600,
    )

allowed_hosts_env = os.getenv("ALLOWED_HOSTS", "").strip()
if allowed_hosts_env:
    allowed_hosts = [host.strip() for host in allowed_hosts_env.split(",") if host.strip()]
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=allowed_hosts)

# Security Headers Middleware
@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    if os.getenv("ENVIRONMENT") == "production":
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; "
        "script-src 'self'; "
        "style-src 'self' 'unsafe-inline'; "
        "img-src 'self' data:; "
        "font-src 'self' data:; "
        "connect-src 'self'; "
        "object-src 'none'; "
        "base-uri 'self'; "
        "form-action 'self'; "
        "frame-ancestors 'none'"
    )
    response.headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
    response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
    return response


@app.middleware("http")
async def add_request_id(request: Request, call_next):
    """Attach a request ID for traceability."""
    supplied_id = request.headers.get("X-Request-ID", "")
    request_id = supplied_id if re.fullmatch(r"[A-Za-z0-9._-]{1,128}", supplied_id) else str(uuid.uuid4())
    token = request_id_ctx.set(request_id)
    try:
        response = await call_next(request)
        response.headers["X-Request-ID"] = request_id
        return response
    finally:
        request_id_ctx.reset(token)


CSRF_SAFE_METHODS = {"GET", "HEAD", "OPTIONS"}
CSRF_EXEMPT_PATHS = {
    "/api/auth/login",
    "/api/auth/register",
}


@app.middleware("http")
async def enforce_csrf(request: Request, call_next):
    if request.method in CSRF_SAFE_METHODS:
        return await call_next(request)
    if not request.url.path.startswith("/api"):
        return await call_next(request)
    if request.url.path in CSRF_EXEMPT_PATHS:
        return await call_next(request)
    if request.headers.get("Authorization"):
        return await call_next(request)
    if "access_token" not in request.cookies:
        return await call_next(request)
    csrf_header = request.headers.get("X-CSRF-Token")
    csrf_cookie = request.cookies.get("csrf_token")
    if not csrf_header or not csrf_cookie or csrf_header != csrf_cookie:
        return api_error("csrf_failed", "CSRF token missing or invalid", status_code=403)
    return await call_next(request)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def validate_wireguard_production_config(logger: logging.Logger, server_count: int) -> None:
    """Log warnings for missing WireGuard production configuration."""
    if not os.getenv("WG_ENCRYPTION_KEY"):
        logger.warning("WG_ENCRYPTION_KEY not set; private keys will not be encrypted at rest.")

    if server_count == 0:
        logger.warning(
            "No VPN servers registered. Run infrastructure/init_production_server.py or "
            "use /api/admin/servers to register a live server."
        )


def validate_production_env(logger: logging.Logger) -> None:
    """Log warnings for missing production environment settings."""
    if os.getenv("ENVIRONMENT", "").lower() != "production":
        return

    required = ["ACCESS_TOKEN_SECRET", "REFRESH_TOKEN_SECRET"]
    for key in required:
        if not os.getenv(key):
            logger.warning(f"{key} is not set in production.")

    cors_origins = os.getenv("CORS_ORIGINS", "").strip()
    if not cors_origins:
        logger.warning("CORS_ORIGINS not set in production.")

    db_url = os.getenv("DATABASE_URL", "").strip()
    if not db_url:
        logger.warning("DATABASE_URL not set in production; SQLite may be used.")
    elif "sqlite" in db_url.lower():
        logger.warning("DATABASE_URL points to SQLite in production; use a managed DB.")

    admin_email = os.getenv("ADMIN_EMAIL", "").strip()
    if admin_email:
        logger.warning("ADMIN_EMAIL is set in production; ensure this is intended.")


def require_encryption_keys(logger: logging.Logger) -> None:
    """Fail fast if encryption keys are missing in production."""
    if not is_production():
        return
    missing = []
    auth_issue = validate_fernet_key(os.getenv("AUTH_ENCRYPTION_KEY"))
    wg_issue = validate_fernet_key(os.getenv("WG_ENCRYPTION_KEY"))
    if auth_issue:
        missing.append(f"AUTH_ENCRYPTION_KEY ({auth_issue})")
    if wg_issue:
        missing.append(f"WG_ENCRYPTION_KEY ({wg_issue})")
    if missing:
        message = f"Missing required encryption keys in production: {', '.join(missing)}"
        logger.error(message)
        raise RuntimeError(message)


def require_production_config(logger: logging.Logger) -> None:
    """Fail fast on production config that must be explicit."""
    if not is_production():
        return

    errors = []
    database_url = os.getenv("DATABASE_URL", "").strip().lower()
    if not database_url or database_url.startswith("sqlite"):
        errors.append("DATABASE_URL must point to a non-SQLite production database")
    if os.getenv("REDIS_URL", "memory://").strip().lower().startswith("memory://"):
        errors.append("REDIS_URL must use a shared production rate-limit backend")
    if not os.getenv("ALLOWED_HOSTS", "").strip():
        errors.append("ALLOWED_HOSTS must be explicitly set in production")

    if errors:
        message = "Production configuration errors: " + "; ".join(errors)
        logger.error(message)
        raise RuntimeError(message)

async def initialize_app_background():
    """Initialize only the app pieces needed by the Linux VPN client."""
    logger = logging.getLogger(__name__)

    if os.getenv("TESTING", "").lower() == "true":
        logger.info("Skipping background initialization in test mode")
        return

    logger.info("Starting background initialization...")

    try:
        from database import base
        from database.session import engine

        base.Base.metadata.create_all(bind=engine)
        logger.info("Database tables ensured")
    except Exception as e:
        logger.warning(f"Database table initialization failed: {e}")

    try:
        app.state.wireguard = WireGuardService()
        logger.info("WireGuard service initialized")
    except Exception as e:
        logger.warning(f"WireGuard service init failed: {e}")

    try:
        with SessionLocal() as db:
            server_count = db.query(vpn_server.VPNServer).count()
            validate_wireguard_production_config(logger, server_count)
        validate_production_env(logger)
    except Exception as e:
        logger.warning(f"Production env validation failed: {e}")

    logger.info("Background initialization completed")




# App routes
app.include_router(new_auth.router, tags=["auth"])  # Already has /api/auth prefix
app.include_router(new_vpn.router, tags=["vpn"])  # Already has /api/vpn prefix
app.include_router(user.router, tags=["user"])


def api_error(code: str, message: str, details=None, status_code: int = 400):
    return JSONResponse(
        status_code=status_code,
        content={
            "error": {
                "code": code,
                "message": redact_text(message),
                "details": sanitize_for_evidence(details) if details is not None else None,
            },
            "request_id": request_id_ctx.get("-"),
        },
    )


@app.get("/health")
def healthcheck():
    return {"status": "ok", "service": "securewave-vpn"}


@app.get("/api/health")
def api_healthcheck():
    return {"status": "ok", "service": "securewave-vpn"}


@app.get("/api/ready")
def readiness():
    db = None
    try:
        db = SessionLocal()
        db.execute(text("SELECT 1"))
        return {"status": "ready", "database": "connected"}
    except Exception:
        logging.getLogger(__name__).warning("Database readiness check failed")
        return JSONResponse(
            status_code=503,
            content={"status": "not_ready", "database": "unavailable"},
        )
    finally:
        if db is not None:
            db.close()


@app.get("/version")
def version():
    return {
        "version": get_app_version(),
        "environment": os.getenv("ENVIRONMENT", "development"),
    }


@app.get("/", include_in_schema=False)
async def root():
    return {"message": "SecureWave VPN API", "docs": "/api/docs"}


@app.exception_handler(404)
async def not_found_handler(request: Request, exc):
    return api_error("not_found", "Not found", status_code=404)


@app.exception_handler(500)
async def internal_error_handler(request: Request, exc):
    logging.getLogger(__name__).error(
        "Internal server error request_id=%s exception_type=%s",
        request_id_ctx.get("-"),
        type(exc).__name__,
    )
    return api_error("internal_error", "Internal server error", status_code=500)


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    return api_error("http_error", exc.detail, status_code=exc.status_code)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    details = safe_validation_errors(exc.errors())
    return api_error("validation_error", "Invalid request", details=details, status_code=422)


"""
Note: For local dev, use `uvicorn main:app --reload`.
Production process managers should run gunicorn with `main:app`.
"""

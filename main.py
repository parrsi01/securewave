import os
import shutil
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
from fastapi.responses import FileResponse, JSONResponse
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.staticfiles import StaticFiles
from release_metadata import get_app_version
from sqlalchemy import text
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from utils.release_identity import get_release_identity
from slowapi.middleware import SlowAPIMiddleware

from database.session import SessionLocal
# Import all models for SQLAlchemy registration - needed for ORM
from models import audit_log, ikev2_credential, openvpn_credential, subscription, user, vpn_connection, vpn_demo_session, vpn_server  # noqa: F401
from routers import contact, dashboard, optimizer, payment_paypal, payment_stripe, admin, security
from routes import auth as new_auth, billing, diagnostics, vpn as new_vpn, servers, devices, vpn_tests, downloads, tools, user
from services.wireguard_service import WireGuardService
from services.email_service import EmailService
from utils.env_validation import (
    email_config_issues,
    validate_fernet_key,
    is_production,
    demo_mode_enabled,
    wg_mock_mode_enabled,
)
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

# NOTE: Table creation is handled exclusively by Alembic migrations.

docs_enabled = os.getenv("ENVIRONMENT") != "production" or os.getenv("DEMO_OK", "false").lower() == "true"


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

    # Shutdown
    logger.info("FastAPI shutdown initiated")
    try:
        from background_tasks import get_task_manager
        task_manager = get_task_manager()
        await task_manager.stop_all()
        logger.info("Background tasks stopped successfully")
    except ModuleNotFoundError:
        pass  # Background tasks weren't loaded, nothing to stop
    except Exception as e:
        logger.warning(f"Failed to stop background tasks: {e}")


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
    "/api/auth/refresh",
    "/api/auth/password-reset/request",
    "/api/auth/password-reset/confirm",
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


def sync_static_assets():
    backend_dir = Path(__file__).resolve().parent
    frontend_dir = backend_dir / "frontend"
    static_dir = backend_dir / "static"
    static_dir.mkdir(parents=True, exist_ok=True)
    if frontend_dir.exists():
        shutil.copytree(frontend_dir, static_dir, dirs_exist_ok=True)


def validate_wireguard_production_config(logger: logging.Logger, server_count: int) -> None:
    """Log warnings for missing WireGuard production configuration."""
    if wg_mock_mode_enabled():
        return
    if demo_mode_enabled():
        return

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
    if os.getenv("EMAIL_PROVIDER") is None:
        errors.append("EMAIL_PROVIDER must be explicitly set in production")
    provider, missing = email_config_issues()
    if missing:
        errors.append(f"EMAIL_PROVIDER({provider}) missing: {', '.join(missing)}")

    for flag in ("DEMO_MODE", "WG_MOCK_MODE"):
        value = os.getenv(flag)
        if value is None:
            errors.append(f"{flag} must be set to false in production")
        elif value.strip().lower() != "false":
            errors.append(f"{flag} must be false in production (got {value})")

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
    """Background initialization that happens AFTER the app starts responding to health checks"""
    logger = logging.getLogger(__name__)

    if os.getenv("TESTING", "").lower() == "true":
        logger.info("Skipping background initialization in test mode")
        return

    # Wait a bit to ensure app is fully started
    await asyncio.sleep(2)

    logger.info("Starting background initialization...")

    try:
        sync_static_assets()
        logger.info("Static assets synced")
    except Exception as e:
        logger.warning(f"Static asset sync failed: {e}")

    try:
        app.state.wireguard = WireGuardService()
        logger.info("WireGuard service initialized")
    except Exception as e:
        logger.warning(f"WireGuard service init failed: {e}")

    # Initialize VPN optimizer with database servers (auto-detects ML availability)
    try:
        from services.vpn_optimizer import get_vpn_optimizer, load_servers_from_database

        optimizer = get_vpn_optimizer()
        db = SessionLocal()

        # Load servers from database
        try:
            server_count = load_servers_from_database(optimizer, db)
            ml_status = "with ML" if optimizer.use_ml else "without ML (dependencies not available)"
            logger.info(f"VPN Optimizer initialized {ml_status} - {server_count} servers from database")

            # If no servers in database, log warning
            if server_count == 0:
                logger.warning("No VPN servers in database.")
                demo_mode = demo_mode_enabled()
                wg_mock = wg_mock_mode_enabled()
                if demo_mode or wg_mock:
                    logger.info("Seeding demo VPN servers for demo mode...")
                    try:
                        from infrastructure.init_demo_servers import init_demo_servers
                        init_demo_servers()
                        server_count = load_servers_from_database(optimizer, db)
                        logger.info(f"Demo servers initialized: {server_count}")
                    except Exception as seed_err:
                        logger.warning(f"Demo server seeding failed: {seed_err}")
                else:
                    logger.warning("Run: python3 infrastructure/init_demo_servers.py")

            validate_wireguard_production_config(logger, server_count)
        except Exception as db_err:
            logger.warning(f"Could not load servers from database: {db_err}. VPN optimizer will start empty.")

        db.close()
    except Exception as e:
        logger.warning(f"VPN Optimizer initialization failed: {e}. Continuing without optimizer.")

    try:
        validate_production_env(logger)
    except Exception as e:
        logger.warning(f"Production env validation failed: {e}")

    # Start background tasks
    try:
        from background_tasks import get_task_manager

        task_manager = get_task_manager()
        await task_manager.start_all()
        logger.info("Background tasks started successfully")
    except ModuleNotFoundError as e:
        logger.warning(f"Background tasks module not found: {e}. Skipping background tasks.")
    except Exception as e:
        logger.warning(f"Background tasks initialization failed: {e}. Continuing without background tasks.")

    logger.info("Background initialization completed")




# New enhanced routes with email verification, 2FA, password reset
app.include_router(new_auth.router, tags=["auth"])  # Already has /api/auth prefix
app.include_router(billing.router, tags=["billing"])  # Already has /api/billing prefix

# New VPN routes (real WireGuard support)
app.include_router(new_vpn.router, tags=["vpn"])  # Already has /api/vpn prefix
app.include_router(vpn_tests.router, tags=["vpn-tests"])  # VPN performance testing
app.include_router(devices.router, tags=["devices"])  # Already has /api/vpn/devices prefix
app.include_router(servers.router, tags=["admin-servers"])  # Already has /api/admin/servers prefix
app.include_router(admin.router, prefix="/api/admin", tags=["admin"])  # Admin peer management

# Supporting routes
app.include_router(optimizer.router, prefix="/api/optimizer", tags=["optimizer"])
app.include_router(dashboard.router, prefix="/api/dashboard", tags=["dashboard"])
app.include_router(payment_stripe.router, prefix="/api/payments", tags=["payments"])
app.include_router(payment_paypal.router, prefix="/api/payments", tags=["payments"])
app.include_router(contact.router, prefix="/api/contact", tags=["contact"])
app.include_router(security.router, prefix="/api/security", tags=["security"])
app.include_router(diagnostics.router, tags=["diagnostics"])
app.include_router(downloads.router, tags=["downloads"])
app.include_router(downloads.public_router, tags=["downloads"])
app.include_router(tools.router, tags=["tools"])
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
    return {"status": "ok", "service": "securewave-vpn-demo"}


@app.get("/api/health")
def api_healthcheck():
    return {"status": "ok", "service": "securewave-vpn-demo"}


@app.get("/api/health/email")
def email_healthcheck():
    service = EmailService()
    status = service.config_status()
    if status["enabled"]:
        return {"status": "ok", "email": status}
    return JSONResponse(status_code=503, content={"status": "not_configured", "email": status})


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
    release_version, release_commit = get_release_identity()
    return {
        "version": release_version,
        "commit": release_commit,
        "environment": os.getenv("ENVIRONMENT", "development"),
    }


static_directory = Path(__file__).resolve().parent / "static"


@app.get("/verify-email", include_in_schema=False)
async def verification_page():
    return FileResponse(
        static_directory / "verify-email.html",
        headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer"},
    )

page_routes = {
    "/home": "index.html",
    "/home.html": "index.html",
    "/favicon.svg": "favicon.svg",
    "/login": "login.html",
    "/register": "register.html",
    "/dashboard": "dashboard.html",
    "/vpn": "vpn.html",
    # Legacy "VPN dashboard control" routes now point to diagnostics/support.
    "/vpn/test": "diagnostics.html",
    "/vpn/results": "diagnostics.html",
    "/settings": "settings.html",
    "/diagnostics": "diagnostics.html",
    "/download": "download.html",
    "/leak-test": "leak_test.html",
    "/subscription": "subscription.html",
    "/services": "services.html",
    "/about": "about.html",
    "/contact": "contact.html",
    "/privacy": "privacy.html",
    "/terms": "terms.html",
}

html_pages = [
    "index.html", "login.html", "register.html",
    "dashboard.html", "vpn.html", "services.html", "subscription.html", "download.html", "leak_test.html",
    "about.html", "contact.html", "privacy.html", "terms.html",
    "settings.html", "diagnostics.html"
]


def make_page_handler(filepath):
    async def handler():
        if filepath.exists():
            return FileResponse(filepath)
        return JSONResponse({"detail": "Not found"}, status_code=404)
    return handler


for route_path, page in page_routes.items():
    app.get(route_path, include_in_schema=False)(make_page_handler(static_directory / page))


for page in html_pages:
    app.get(f"/{page}", include_in_schema=False)(make_page_handler(static_directory / page))

# Mount static assets (CSS, JS, images, etc.) under /static and root
# Note: We mount unconditionally - Starlette will handle missing directories gracefully
_logger = logging.getLogger(__name__)
_logger.info(f"Static directory path: {static_directory}")
_logger.info(f"Static directory exists: {static_directory.exists()}")
if static_directory.exists():
    _logger.info(f"Static directory contents: {list(static_directory.iterdir()) if static_directory.exists() else 'N/A'}")

try:
    app.mount("/static", StaticFiles(directory=str(static_directory)), name="static")
    css_dir = static_directory / "css"
    js_dir = static_directory / "js"
    img_dir = static_directory / "img"
    if css_dir.exists():
        app.mount("/css", StaticFiles(directory=str(css_dir)), name="css")
    if js_dir.exists():
        app.mount("/js", StaticFiles(directory=str(js_dir)), name="js")
    if img_dir.exists():
        app.mount("/img", StaticFiles(directory=str(img_dir)), name="img")
    _logger.info("Static files mounted successfully")
except Exception as e:
    _logger.warning(f"Failed to mount static files: {e}")


@app.get("/", include_in_schema=False)
async def root():
    index_file = static_directory / "index.html"
    if index_file.exists():
        return FileResponse(index_file)
    return {"message": "SecureWave VPN API", "docs": "/api/docs"}


@app.exception_handler(404)
async def not_found_handler(request: Request, exc):
    # Check if it's an API request
    if request.url.path.startswith("/api"):
        return api_error("not_found", "Not found", status_code=404)

    # For web requests, show custom 404 page
    error_404 = static_directory / "404.html"
    if error_404.exists():
        return FileResponse(error_404, status_code=404)
    return JSONResponse({"detail": "Not found"}, status_code=404)


@app.exception_handler(500)
async def internal_error_handler(request: Request, exc):
    _logger.error(
        "Internal server error request_id=%s exception_type=%s",
        request_id_ctx.get("-"),
        type(exc).__name__,
    )

    # For API requests, return JSON
    if request.url.path.startswith("/api"):
        return api_error("internal_error", "Internal server error", status_code=500)

    # For web requests, show error page
    error_page = static_directory / "error.html"
    if error_page.exists():
        return FileResponse(error_page, status_code=500)
    return JSONResponse({"detail": "Internal server error"}, status_code=500)


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    if request.url.path.startswith("/api"):
        return api_error("http_error", exc.detail, status_code=exc.status_code)
    return JSONResponse({"detail": exc.detail}, status_code=exc.status_code)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    details = safe_validation_errors(exc.errors())
    if request.url.path.startswith("/api"):
        return api_error("validation_error", "Invalid request", details=details, status_code=422)
    return JSONResponse({"detail": "Invalid request"}, status_code=422)


"""
Note: For local dev, use `uvicorn main:app --reload`.
Production process managers should run gunicorn with `main:app`.
"""

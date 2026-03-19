import os
import shutil
import asyncio
import logging
import re
import uuid
from datetime import datetime, timezone
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request, HTTPException, status, Depends
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, PlainTextResponse
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from sqlalchemy.orm import Session
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from database.session import SessionLocal
# Import all models for SQLAlchemy registration - needed for ORM
from models import user, subscription, payment_idempotency_key, webhook_event_receipt, audit_log, vpn_server, vpn_server_rtt_sample, vpn_connection, vpn_credential, auth_refresh_token, jwt_blacklist_token, used_totp_code  # noqa: F401
from routers import contact, dashboard, optimizer, payment_paypal, payment_stripe, admin, security
from routes import auth as new_auth, billing, diagnostics, vpn as new_vpn, servers, devices, vpn_tests, downloads, tools, user, vpn_metrics
from config.security_config import enforce_permission_policy, secret_file_candidates
from services.wireguard_service import WireGuardService
from services.email_service import EmailService
from services.runtime_metrics import get_runtime_metrics
from services.server_bootstrap import ensure_default_servers
from services.tunnel_runtime import ensure_tunnel_mode_allowed
from services.jwt_service import get_current_user
from services.vpn_peer_manager import get_peer_manager
from models.user import User
from models.wireguard_peer import WireGuardPeer
from utils.api_errors import ApiException, ApiErrorResponse
from utils.env_validation import (
    email_config_issues,
    validate_fernet_key,
    is_production,
)
from utils.structured_logging import (
    configure_structured_logging,
    log_security_event,
    request_id_ctx,
    sanitize_for_log,
)


class RedactFilter(logging.Filter):
    """Redact emails and obvious secrets from log messages."""
    _email_re = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
    _token_re = re.compile(r"(Bearer\s+)[A-Za-z0-9._\-]+", re.IGNORECASE)
    _stripe_sk_re = re.compile(r"\bsk_(?:live|test)_[A-Za-z0-9]+\b")
    _stripe_whsec_re = re.compile(r"\bwhsec_[A-Za-z0-9]+\b")
    _wg_priv_re = re.compile(r"(PrivateKey\s*=\s*)([^\s]+)")
    _wg_psk_re = re.compile(r"(PresharedKey\s*=\s*)([^\s]+)")
    _jwt_secret_re = re.compile(r"((?:JWT_SECRET|SECRET_KEY|ACCESS_TOKEN_SECRET|REFRESH_TOKEN_SECRET)=)([^\s]+)")

    def filter(self, record: logging.LogRecord) -> bool:
        message = record.getMessage()
        message = self._email_re.sub("[redacted-email]", message)
        message = self._token_re.sub(r"\1[redacted-token]", message)
        message = self._stripe_sk_re.sub("[redacted-stripe-secret]", message)
        message = self._stripe_whsec_re.sub("[redacted-stripe-webhook-secret]", message)
        # Defensive: never emit WireGuard secrets if a config blob is accidentally logged.
        message = self._wg_priv_re.sub(r"\1[redacted-wg-privatekey]", message)
        message = self._wg_psk_re.sub(r"\1[redacted-wg-psk]", message)
        message = self._jwt_secret_re.sub(r"\1[redacted-secret]", message)
        record.msg = message
        record.args = ()
        record.request_id = request_id_ctx.get("-")
        return True

LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
configure_structured_logging(LOG_LEVEL)

# NOTE: Table creation is handled by Alembic migrations in Dockerfile CMD
# base.Base.metadata.create_all(bind=engine)  # Commented out to avoid conflicts with migrations

docs_enabled = os.getenv("ENVIRONMENT", "development").strip().lower() != "production"


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

    apply_runtime_permission_policy(logger)
    require_encryption_keys(logger)
    require_production_config(logger)
    ensure_tunnel_mode_allowed()

    if os.getenv("TESTING", "").lower() != "true":
        db = None
        try:
            db = SessionLocal()
            ensure_default_servers(db)
        except Exception as e:
            logger.warning(f"Default VPN server bootstrap skipped: {e}")
        finally:
            if db is not None:
                db.close()

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
    version="1.0.0",
    docs_url="/api/docs" if docs_enabled else None,
    redoc_url="/api/redoc" if docs_enabled else None,
    openapi_url="/api/openapi.json" if docs_enabled else None,
    lifespan=lifespan,
    responses={
        400: {"model": ApiErrorResponse, "description": "Bad request"},
        401: {"model": ApiErrorResponse, "description": "Unauthorized"},
        403: {"model": ApiErrorResponse, "description": "Forbidden"},
        404: {"model": ApiErrorResponse, "description": "Not found"},
        409: {"model": ApiErrorResponse, "description": "Conflict"},
        422: {"model": ApiErrorResponse, "description": "Validation error"},
        429: {"model": ApiErrorResponse, "description": "Rate limited"},
        500: {"model": ApiErrorResponse, "description": "Internal server error"},
        503: {"model": ApiErrorResponse, "description": "Service unavailable"},
    },
)

is_testing = os.getenv("TESTING", "").lower() == "true"
app.add_middleware(GZipMiddleware, minimum_size=500)

# Rate Limiting Configuration
# In production, REDIS_URL must be set so rate limits are shared across all
# Gunicorn workers.  Memory-based rate limiting is per-process and silently
# allows N×limit requests when running with N workers.
_redis_url = os.getenv("REDIS_URL", "")
_is_production = os.getenv("ENVIRONMENT", "development").strip().lower() == "production"
if _is_production and not _redis_url and not is_testing:
    import logging as _logging
    _logging.getLogger(__name__).warning(
        "REDIS_URL not set in production — using memory:// rate limiting. "
        "This is per-process and ineffective with multiple Gunicorn workers. "
        "Set REDIS_URL to a Redis instance."
    )
limiter = Limiter(
    key_func=get_remote_address,
    storage_uri=_redis_url or "memory://",
    default_limits=["200 per minute"]
)
app.state.limiter = limiter
if not is_testing:
    app.add_middleware(SlowAPIMiddleware)


@app.exception_handler(RateLimitExceeded)
async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    get_runtime_metrics().record_rate_limited()
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

# Security Headers Middleware
@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains; preload"
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; "
        # script-src: no 'unsafe-inline' or 'unsafe-eval' — strictest possible without nonces
        "script-src 'self'; "
        # L-14: style-src retains 'unsafe-inline' because 74 inline style attributes exist
        # across 14 static HTML pages. Removing it requires migrating all inline styles to
        # external stylesheets or adding nonce-based CSP — tracked as a template refactor task.
        "style-src 'self' 'unsafe-inline'; "
        "img-src 'self' data:; "
        "font-src 'self' data:; "
        "connect-src 'self'; "
        "object-src 'none'; "
        "base-uri 'self'; "
        "form-action 'self'; "
        "frame-ancestors 'none'"
    )
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
    return response


@app.middleware("http")
async def enforce_https_forwarded_proto(request: Request, call_next):
    """
    Production guardrail: reject non-HTTPS proxy forwarding metadata.
    """
    if os.getenv("ENVIRONMENT", "").lower() == "production":
        forwarded_proto = request.headers.get("X-Forwarded-Proto", "")
        if forwarded_proto:
            primary_proto = forwarded_proto.split(",")[0].strip().lower()
            if primary_proto != "https":
                return api_error(
                    "https_required",
                    "HTTPS is required",
                    status_code=400,
                )
        elif request.url.scheme.lower() != "https":
            return api_error(
                "https_required",
                "HTTPS is required",
                status_code=400,
            )
    return await call_next(request)


@app.middleware("http")
async def add_request_id(request: Request, call_next):
    """Attach a request ID for traceability."""
    raw_request_id = request.headers.get("X-Request-ID", "")
    request_id = sanitize_for_log(raw_request_id, max_len=64) if raw_request_id else str(uuid.uuid4())
    request_id_ctx.set(request_id)
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    return response


REVOCATION_EXEMPT_PATHS = {
    "/api/auth/login",
    "/api/auth/register",
    "/api/auth/refresh",
    "/api/auth/revoke-token",
}


@app.middleware("http")
async def enforce_revoked_access_token(request: Request, call_next):
    if request.url.path in REVOCATION_EXEMPT_PATHS:
        return await call_next(request)

    token = None
    auth_header = request.headers.get("Authorization", "")
    if auth_header.lower().startswith("bearer "):
        token = auth_header.split(" ", 1)[1].strip()
    elif "access_token" in request.cookies:
        token = request.cookies.get("access_token")

    if token:
        try:
            from services.jwt_service import ACCESS_SECRET, decode_token, is_token_jti_revoked

            payload = decode_token(token, ACCESS_SECRET)
            if payload.get("type") == "access":
                db = SessionLocal()
                try:
                    if is_token_jti_revoked(db, payload.get("jti")):
                        return api_error("token_revoked", "Token revoked", status_code=401)
                finally:
                    db.close()
        except HTTPException:
            # Existing auth handlers will process invalid/expired token cases.
            pass
        except Exception:
            pass

    return await call_next(request)


CSRF_SAFE_METHODS = {"GET", "HEAD", "OPTIONS"}
CSRF_EXEMPT_PATHS = {
    "/api/auth/login",
    "/api/auth/register",
    "/api/auth/password-reset/request",
}


@app.middleware("http")
async def enforce_csrf(request: Request, call_next):
    if request.method in CSRF_SAFE_METHODS:
        return await call_next(request)
    if not request.url.path.startswith("/api"):
        return await call_next(request)
    if request.url.path in CSRF_EXEMPT_PATHS:
        return await call_next(request)
    # CSRF only applies to cookie-based sessions.
    # Pure Bearer-only clients (no auth cookies) are not vulnerable
    # to CSRF because browsers cannot attach Authorization headers cross-origin.
    access_cookie = request.cookies.get("access_token", "")
    refresh_cookie = request.cookies.get("refresh_token", "")
    if not access_cookie and not refresh_cookie:
        return await call_next(request)
    # If the Authorization Bearer token exactly matches one of the auth cookies,
    # the caller has read-access to the cookie (proves same-origin).
    # A cross-site attacker cannot read httpOnly cookies, so this cannot be forged.
    # NOTE: We require equality — merely having an Authorization header is NOT sufficient.
    auth_header = request.headers.get("Authorization", "")
    bearer_token = auth_header[7:].strip() if auth_header.lower().startswith("bearer ") else ""
    if bearer_token and bearer_token in {access_cookie, refresh_cookie}:
        return await call_next(request)
    csrf_header = request.headers.get("X-CSRF-Token")
    csrf_cookie = request.cookies.get("csrf_token")
    if not csrf_header or not csrf_cookie or csrf_header != csrf_cookie:
        log_security_event(
            "auth_failure",
            "medium",
            reason="csrf_failed",
            ip_address=sanitize_for_log(request.client.host if request.client else "unknown", 64),
            path=sanitize_for_log(str(request.url.path), 256),
            method=request.method,
        )
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
    if not os.getenv("WG_ENCRYPTION_KEY"):
        logger.warning("WG_ENCRYPTION_KEY not set; private keys will not be encrypted at rest.")

    if server_count == 0:
        logger.warning(
            "No VPN servers registered. Register a live Hetzner WireGuard server via "
            "python3 infrastructure/hetzner/sync_vpn_servers.py (recommended) or "
            "use /api/admin/servers to register manually."
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
    if os.getenv("TESTING", "").strip().lower() == "true":
        errors.append("TESTING must not be true in production")
    if os.getenv("EMAIL_PROVIDER") is None:
        errors.append("EMAIL_PROVIDER must be explicitly set in production")
    provider, missing = email_config_issues()
    if missing:
        errors.append(f"EMAIL_PROVIDER({provider}) missing: {', '.join(missing)}")

    if errors:
        message = "Production configuration errors: " + "; ".join(errors)
        logger.error(message)
        raise RuntimeError(message)


def apply_runtime_permission_policy(logger: logging.Logger) -> None:
    permission_targets = list(secret_file_candidates())
    runtime_dirs = [Path.home() / ".config" / "securewave", Path.home() / ".local" / "state" / "securewave"]
    permission_targets.extend(path for path in runtime_dirs if path.exists())
    if not permission_targets:
        return

    permission_result = enforce_permission_policy(permission_targets)
    for warning in permission_result.warnings:
        logger.warning(warning, extra={"event": "permission_policy"})

def _reconcile_wg_pubkeys(logger: logging.Logger) -> None:
    """Compare running wg0 public key against DB and auto-correct mismatches."""
    import subprocess
    try:
        result = subprocess.run(
            ["wg", "show", "wg0", "public-key"],
            capture_output=True, text=True, timeout=5,
        )
        if result.returncode != 0:
            logger.debug("wg show wg0 public-key failed (wg0 may not exist on this host)")
            return
        runtime_key = result.stdout.strip()
        if not runtime_key:
            return
    except FileNotFoundError:
        logger.debug("wg binary not found — skipping pubkey reconciliation")
        return

    from database.session import SessionLocal
    from models.vpn_server import VPNServer

    db = SessionLocal()
    try:
        # Find servers on this host whose DB key doesn't match the running key.
        # All servers sharing the same wg0 interface must share the same pubkey.
        stale = (
            db.query(VPNServer)
            .filter(
                VPNServer.wg_public_key != runtime_key,
                VPNServer.supports_wireguard.is_(True),
            )
            .all()
        )
        for srv in stale:
            logger.warning(
                "[WG_KEY_MISMATCH] server=%s db_key=%.12s… runtime_key=%.12s… — auto-correcting",
                srv.server_id, srv.wg_public_key, runtime_key,
            )
            srv.wg_public_key = runtime_key
        if stale:
            db.commit()
            logger.info("Corrected WG public key for %d server(s)", len(stale))
    finally:
        db.close()


async def initialize_app_background():
    """Background initialization that happens AFTER the app starts responding to health checks"""
    logger = logging.getLogger(__name__)

    if os.getenv("TESTING", "").lower() == "true":
        logger.info("Skipping background initialization in test mode")
        return

    # Wait a bit to ensure app is fully started
    await asyncio.sleep(2)

    logger.info("Starting background initialization...")

    # Initialize database tables
    try:
        from database.session import create_tables
        logger.info("Creating database tables...")
        create_tables()
        logger.info("Database tables created successfully")
    except Exception as e:
        logger.warning(f"Database initialization failed: {e}")

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

            validate_wireguard_production_config(logger, server_count)
        except Exception as db_err:
            logger.warning(f"Could not load servers from database: {db_err}. VPN optimizer will start empty.")

        db.close()
    except Exception as e:
        logger.warning(f"VPN Optimizer initialization failed: {e}. Continuing without optimizer.")

    # Self-heal stale WireGuard public keys: compare runtime wg0 key
    # against DB entries for this host.  Prevents handshake failures
    # caused by key drift (e.g. wg0 regenerated but DB not updated).
    try:
        _reconcile_wg_pubkeys(logger)
    except Exception as e:
        logger.warning(f"WG pubkey reconciliation failed (non-fatal): {e}")

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
app.include_router(vpn_metrics.router, tags=["vpn-metrics"])
app.include_router(downloads.router, tags=["downloads"])
app.include_router(tools.router, tags=["tools"])
app.include_router(user.router, tags=["user"])
app.include_router(user.account_router, tags=["account"])


HTTP_STATUS_TO_CODE = {
    400: "bad_request",
    401: "unauthorized",
    403: "forbidden",
    404: "not_found",
    405: "method_not_allowed",
    409: "conflict",
    422: "validation_error",
    429: "rate_limited",
    500: "internal_error",
    502: "bad_gateway",
    503: "service_unavailable",
    504: "gateway_timeout",
}


def api_error(code: str, message: str, details=None, status_code: int = 400):
    return JSONResponse(
        status_code=status_code,
        content={
            "error": {"code": code, "message": message, "details": details},
            "request_id": request_id_ctx.get("-"),
        },
    )


@app.get("/health")
def healthcheck():
    return {"status": "ok", "service": "securewave-vpn"}


@app.get("/api/health")
def api_healthcheck():
    return {"status": "ok", "service": "securewave-vpn"}


@app.get("/api/health/email")
def email_healthcheck():
    service = EmailService()
    status = service.config_status()
    if status["enabled"]:
        return {"status": "ok", "email": status}
    return JSONResponse(status_code=503, content={"status": "not_configured", "email": status})


@app.get("/api/ready")
def readiness():
    try:
        db = SessionLocal()
        db.execute(text("SELECT 1"))
        db.close()
        return {"status": "ready", "database": "connected"}
    except Exception as e:
        # Ops signal: return non-200 when not ready, and don't leak internal DB details.
        _logger.warning("Readiness check failed", exc_info=True)
        return JSONResponse(status_code=503, content={"status": "not_ready", "database": "unavailable"})


@app.get("/version")
def version():
    return {"version": os.getenv("APP_VERSION", "dev")}


@app.get("/metrics", include_in_schema=False)
def prometheus_metrics(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not current_user.is_admin:
        raise HTTPException(status_code=403, detail="Admin required")
    """
    Prometheus-compatible metrics export with fleet gauges.
    """
    from models.vpn_server import VPNServer
    from models.vpn_connection import VPNConnection

    active_sessions = (
        db.query(VPNConnection)
        .filter(VPNConnection.disconnected_at.is_(None))
        .count()
    )
    active_tunnels = (
        db.query(WireGuardPeer)
        .filter(WireGuardPeer.is_revoked == False, WireGuardPeer.is_active == True)
        .count()
    )
    servers = db.query(VPNServer).filter(VPNServer.status == "active").all()
    total_servers = len(servers)

    fleet = {
        "active_sessions": active_sessions,
        "active_tunnels": active_tunnels,
        "total_servers": total_servers,
        "healthy_servers": sum(1 for s in servers if s.health_status == "healthy"),
        "total_connections": sum(s.current_connections for s in servers),
        "avg_load_score": (
            round(sum(s.load_score or 0.0 for s in servers) / total_servers, 4)
            if total_servers else 0.0
        ),
    }

    return PlainTextResponse(
        content=get_runtime_metrics().export_prometheus(fleet=fleet),
        media_type="text/plain; version=0.0.4",
    )


@app.get("/api/metrics/vpn")
def api_vpn_metrics(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    JSON VPN performance metrics export.
    """
    peer_manager = get_peer_manager(db)
    pool = peer_manager.get_ip_pool_stats()
    runtime = get_runtime_metrics().snapshot()

    total = db.query(WireGuardPeer).filter(WireGuardPeer.is_revoked == False).count()
    healthy = db.query(WireGuardPeer).filter(
        WireGuardPeer.is_revoked == False,
        WireGuardPeer.health_status == "healthy",
    ).count()
    degraded = db.query(WireGuardPeer).filter(
        WireGuardPeer.is_revoked == False,
        WireGuardPeer.health_status == "degraded",
    ).count()
    unstable = db.query(WireGuardPeer).filter(
        WireGuardPeer.is_revoked == False,
        WireGuardPeer.health_status == "unstable",
    ).count()

    classification = "healthy"
    if total > 0 and unstable / total >= 0.25:
        classification = "unstable"
    elif degraded > 0 or unstable > 0:
        classification = "degraded"

    return {
        "health_classification": classification,
        "peers": {
            "total": total,
            "healthy": healthy,
            "degraded": degraded,
            "unstable": unstable,
        },
        "ip_pool": pool,
        "runtime": runtime,
    }


@app.get("/api/metrics/system")
def api_system_metrics(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    JSON system/process metrics for leak/FD/memory audits.
    """
    runtime = get_runtime_metrics().snapshot()

    peer_total = db.query(WireGuardPeer).count()
    peer_active = db.query(WireGuardPeer).filter(
        WireGuardPeer.is_revoked == False,
        WireGuardPeer.is_active == True,
    ).count()
    peer_revoked = db.query(WireGuardPeer).filter(WireGuardPeer.is_revoked == True).count()

    # "Zombie peers": inconsistent DB state that should not exist long-term.
    zombie_peers = db.query(WireGuardPeer).filter(
        WireGuardPeer.is_revoked == False,
        WireGuardPeer.is_active == False,
    ).count()

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "runtime": runtime,
        "wireguard_peers": {
            "total": peer_total,
            "active": peer_active,
            "revoked": peer_revoked,
            "zombie": zombie_peers,
        },
    }


@app.get("/api/metrics")
def api_fleet_metrics(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Unified production metrics: active sessions, server load, tunnel count.

    Returns fleet-wide operational gauges for monitoring dashboards.
    """
    from models.vpn_server import VPNServer
    from models.vpn_connection import VPNConnection

    # Active VPN sessions (connections with no disconnected_at).
    active_sessions = (
        db.query(VPNConnection)
        .filter(VPNConnection.disconnected_at.is_(None))
        .count()
    )

    # Active WireGuard tunnels (non-revoked, active peers).
    active_tunnels = (
        db.query(WireGuardPeer)
        .filter(
            WireGuardPeer.is_revoked == False,
            WireGuardPeer.is_active == True,
        )
        .count()
    )

    # Server fleet metrics.
    servers = (
        db.query(VPNServer)
        .filter(VPNServer.status == "active")
        .all()
    )
    total_servers = len(servers)
    healthy_servers = sum(1 for s in servers if s.health_status == "healthy")
    total_capacity = sum(s.max_connections for s in servers) or 1
    total_connections = sum(s.current_connections for s in servers)
    avg_load_score = (
        round(sum(s.load_score or 0.0 for s in servers) / total_servers, 4)
        if total_servers
        else 0.0
    )

    runtime = get_runtime_metrics().snapshot()

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "active_sessions": active_sessions,
        "active_tunnels": active_tunnels,
        "fleet": {
            "total_servers": total_servers,
            "healthy_servers": healthy_servers,
            "total_connections": total_connections,
            "total_capacity": total_capacity,
            "capacity_pct": round(total_connections / total_capacity * 100, 2),
            "avg_load_score": avg_load_score,
        },
        "runtime": runtime,
    }


static_directory = Path(__file__).resolve().parent / "static"

page_routes = {
    "/home": "home.html",
    "/login": "login.html",
    "/register": "register.html",
    "/forgot-password": "forgot_password.html",
    "/reset-password": "reset_password.html",
    "/dashboard": "dashboard.html",
    "/vpn": "vpn.html",
    # Legacy "VPN dashboard control" routes now point to diagnostics/support.
    "/vpn/test": "diagnostics.html",
    "/vpn/results": "diagnostics.html",
    "/settings": "settings.html",
    "/diagnostics": "diagnostics.html",
    "/download": "download.html",
    "/leak-test": "leak_test.html",
    "/billing": "billing.html",
    "/subscription": "subscription.html",
    "/services": "services.html",
    "/about": "about.html",
    "/contact": "contact.html",
    "/privacy": "privacy.html",
    "/terms": "terms.html",
    "/data_retention": "data_retention.html",
    "/acceptable_use": "acceptable_use.html",
    "/status": "status.html",
    "/faq": "faq.html",
    "/support": "faq.html",
    "/help": "faq.html",
}

html_pages = [
    "index.html", "home.html", "login.html", "register.html",
    "dashboard.html", "vpn.html", "services.html", "subscription.html", "download.html", "leak_test.html",
    "about.html", "contact.html", "privacy.html", "terms.html", "data_retention.html", "acceptable_use.html",
    "settings.html", "diagnostics.html", "billing.html", "status.html", "faq.html",
    "forgot_password.html", "reset_password.html",
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


# SEO / crawler files served from static root
@app.get("/robots.txt", include_in_schema=False)
async def robots_txt():
    return FileResponse(static_directory / "robots.txt", media_type="text/plain")


@app.get("/sitemap.xml", include_in_schema=False)
async def sitemap_xml():
    return FileResponse(static_directory / "sitemap.xml", media_type="application/xml")


# Redirect legacy/missing routes to nearest equivalent pages
@app.get("/pricing", include_in_schema=False)
async def pricing_redirect():
    from fastapi.responses import RedirectResponse
    return RedirectResponse(url="/subscription", status_code=301)


@app.get("/features", include_in_schema=False)
async def features_redirect():
    from fastapi.responses import RedirectResponse
    return RedirectResponse(url="/services", status_code=301)


@app.get("/downloads", include_in_schema=False)
async def downloads_redirect():
    from fastapi.responses import RedirectResponse
    return RedirectResponse(url="/download", status_code=301)


@app.get("/account", include_in_schema=False)
async def account_redirect():
    from fastapi.responses import RedirectResponse
    return RedirectResponse(url="/settings", status_code=301)


@app.get("/profile", include_in_schema=False)
async def profile_redirect():
    from fastapi.responses import RedirectResponse
    return RedirectResponse(url="/settings", status_code=301)

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
    downloads_dir = static_directory / "downloads"
    if css_dir.exists():
        app.mount("/css", StaticFiles(directory=str(css_dir)), name="css")
    if js_dir.exists():
        app.mount("/js", StaticFiles(directory=str(js_dir)), name="js")
    if img_dir.exists():
        app.mount("/img", StaticFiles(directory=str(img_dir)), name="img")
    if downloads_dir.exists():
        app.mount("/downloads", StaticFiles(directory=str(downloads_dir)), name="downloads")
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
    _logger.error(f"Internal server error: {exc}")

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
        if isinstance(exc, ApiException):
            return api_error(
                exc.code,
                exc.message,
                details=exc.details,
                status_code=exc.status_code,
            )
        code = HTTP_STATUS_TO_CODE.get(exc.status_code, "http_error")
        return api_error(code, str(exc.detail), status_code=exc.status_code)
    return JSONResponse({"detail": exc.detail}, status_code=exc.status_code)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    # L-12: Return a generic error without field paths/types to avoid leaking
    # internal schema details (field names, loc paths, type strings) to clients.
    # The full error is logged server-side for debugging.
    _logger.debug("Validation error on %s: %s", request.url.path, exc.errors())
    if request.url.path.startswith("/api"):
        return api_error("validation_error", "Invalid request parameters", status_code=422)
    return JSONResponse({"detail": "Invalid request parameters"}, status_code=422)


"""
Note: For local dev, use `uvicorn main:app --reload`.
Production uses gunicorn managed by systemd or Docker (see docs/HETZNER_RUNBOOK.md).
"""

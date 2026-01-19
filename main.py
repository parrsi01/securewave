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
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from database.session import SessionLocal
# Import all models for SQLAlchemy registration - needed for ORM
from models import user, subscription, audit_log, vpn_server, vpn_connection, vpn_demo_session  # noqa: F401
from routers import contact, dashboard, optimizer, payment_paypal, payment_stripe, admin
from routes import auth as new_auth, billing, diagnostics, vpn as new_vpn, servers, devices, vpn_tests
from services.wireguard_service import WireGuardService

# Request ID context
request_id_ctx = contextvars.ContextVar("request_id", default="-")


class RedactFilter(logging.Filter):
    """Redact emails and obvious secrets from log messages."""
    _email_re = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
    _token_re = re.compile(r"(Bearer\\s+)[A-Za-z0-9._\\-]+")

    def filter(self, record: logging.LogRecord) -> bool:
        message = record.getMessage()
        message = self._email_re.sub("[redacted-email]", message)
        message = self._token_re.sub(r"\\1[redacted-token]", message)
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

# NOTE: Table creation is handled by Alembic migrations in Dockerfile CMD
# base.Base.metadata.create_all(bind=engine)  # Commented out to avoid conflicts with migrations

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
)

is_testing = os.getenv("TESTING", "").lower() == "true"

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

# Security Headers Middleware
@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    if os.getenv("ENVIRONMENT") == "production":
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["Content-Security-Policy"] = "default-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob:;"
    return response


@app.middleware("http")
async def add_request_id(request: Request, call_next):
    """Attach a request ID for traceability."""
    request_id = request.headers.get("X-Request-ID") or str(uuid.uuid4())
    request_id_ctx.set(request_id)
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    return response


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
    if os.getenv("WG_MOCK_MODE", "false").lower() == "true":
        return
    if os.getenv("DEMO_MODE", "false").lower() == "true":
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
        from database import base
        from database.session import engine
        logger.info("Creating database tables...")
        base.Base.metadata.create_all(bind=engine)
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
                demo_mode = os.getenv("DEMO_MODE", "true").lower() == "true"
                wg_mock = os.getenv("WG_MOCK_MODE", "").lower() == "true"
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
app.include_router(diagnostics.router, tags=["diagnostics"])


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
    return {"status": "ok", "service": "securewave-vpn-demo"}


@app.get("/api/health")
def api_healthcheck():
    return {"status": "ok", "service": "securewave-vpn-demo"}


@app.get("/api/ready")
def readiness():
    try:
        db = SessionLocal()
        db.execute(text("SELECT 1"))
        db.close()
        return {"status": "ready", "database": "connected"}
    except Exception as e:
        return {"status": "not_ready", "error": str(e)}


@app.get("/version")
def version():
    return {
        "version": os.getenv("APP_VERSION", "dev"),
        "commit": os.getenv("GIT_SHA", ""),
        "environment": os.getenv("ENVIRONMENT", "development"),
    }


static_directory = Path(__file__).resolve().parent / "static"

page_routes = {
    "/": "index.html",
    "/home": "home.html",
    "/login": "login.html",
    "/register": "register.html",
    "/dashboard": "dashboard.html",
    "/vpn": "vpn.html",
    "/vpn/test": "vpn.html",
    "/vpn/results": "vpn.html",
    "/settings": "settings.html",
    "/diagnostics": "diagnostics.html",
    "/subscription": "subscription.html",
    "/services": "services.html",
    "/about": "about.html",
    "/contact": "contact.html",
    "/privacy": "privacy.html",
    "/terms": "terms.html",
    "/admin-vpn": "admin-vpn.html",
}

html_pages = [
    "index.html", "home.html", "login.html", "register.html",
    "dashboard.html", "vpn.html", "services.html", "subscription.html",
    "about.html", "contact.html", "privacy.html", "terms.html",
    "settings.html", "diagnostics.html", "admin-vpn.html"
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
import logging
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
    assets_dir = static_directory / "assets"
    if css_dir.exists():
        app.mount("/css", StaticFiles(directory=str(css_dir)), name="css")
    if js_dir.exists():
        app.mount("/js", StaticFiles(directory=str(js_dir)), name="js")
    if img_dir.exists():
        app.mount("/img", StaticFiles(directory=str(img_dir)), name="img")
    if assets_dir.exists():
        app.mount("/assets", StaticFiles(directory=str(assets_dir)), name="assets")
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
    import logging
    logger = logging.getLogger(__name__)
    logger.error(f"Internal server error: {exc}")

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
    if request.url.path.startswith("/api"):
        return api_error("validation_error", "Invalid request", details=exc.errors(), status_code=422)
    return JSONResponse({"detail": exc.errors()}, status_code=422)


"""
Note: For local dev, use `uvicorn main:app --reload`.
Azure App Service uses gunicorn with the startup command in AZURE_DEPLOY.md.
"""

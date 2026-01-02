import os
import shutil
from pathlib import Path

from fastapi import Depends, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

from database import base  # noqa: F401
from database.session import SessionLocal, engine
# Import all models for SQLAlchemy registration
from models import user, subscription, audit_log, vpn_server, vpn_connection  # noqa: F401
from routers import auth, contact, dashboard, optimizer, payment_paypal, payment_stripe, vpn
from services.wireguard_service import WireGuardService

# NOTE: Table creation is handled by Alembic migrations in Dockerfile CMD
# base.Base.metadata.create_all(bind=engine)  # Commented out to avoid conflicts with migrations

app = FastAPI(
    title="SecureWave VPN",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json",
)

# Rate Limiting Configuration
limiter = Limiter(
    key_func=get_remote_address,
    storage_uri=os.getenv("REDIS_URL", "memory://"),
    default_limits=["200 per minute"]
)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS Configuration - Locked Down for Production
origins_env = os.getenv("CORS_ORIGINS", "")
if origins_env:
    origins = [o.strip() for o in origins_env.split(",") if o.strip()]
else:
    # Development defaults
    origins = ["http://localhost:3000", "http://localhost:8000", "http://127.0.0.1:8000"]

# Security check: No wildcards in production
if os.getenv("ENVIRONMENT") == "production" and ("*" in origins or not origins_env):
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


@app.on_event("startup")
async def startup_event():
    import logging
    logger = logging.getLogger(__name__)

    try:
        sync_static_assets()
    except Exception as e:
        logger.warning(f"Static asset sync failed: {e}")

    try:
        app.state.wireguard = WireGuardService()
    except Exception as e:
        logger.warning(f"WireGuard service init failed: {e}")

    # Initialize VPN optimizer with database servers
    try:
        from services.vpn_optimizer import get_vpn_optimizer, load_servers_from_database

        optimizer = get_vpn_optimizer()
        db = SessionLocal()

        # Load servers from database
        server_count = load_servers_from_database(optimizer, db)
        logger.info(f"VPN Optimizer initialized with {server_count} servers from database")

        # If no servers in database, initialize demo servers for development
        if server_count == 0:
            logger.warning("No servers in database. Run: python3 infrastructure/init_demo_servers.py")

        db.close()
    except Exception as e:
        logger.error(f"VPN Optimizer initialization failed: {e}", exc_info=True)

    # Start background tasks
    try:
        from background_tasks import get_task_manager

        task_manager = get_task_manager()
        await task_manager.start_all()
        logger.info("Background tasks started successfully")
    except Exception as e:
        logger.error(f"Background tasks initialization failed: {e}", exc_info=True)


@app.on_event("shutdown")
async def shutdown_event():
    import logging
    logger = logging.getLogger(__name__)

    # Stop background tasks
    try:
        from background_tasks import get_task_manager

        task_manager = get_task_manager()
        await task_manager.stop_all()
        logger.info("Background tasks stopped successfully")
    except Exception as e:
        logger.error(f"Failed to stop background tasks: {e}", exc_info=True)


app.include_router(auth.router, prefix="/api/auth", tags=["auth"])
app.include_router(vpn.router, prefix="/api/vpn", tags=["vpn"])
app.include_router(optimizer.router, prefix="/api/optimizer", tags=["optimizer"])
app.include_router(dashboard.router, prefix="/api/dashboard", tags=["dashboard"])
app.include_router(payment_stripe.router, prefix="/api/payments", tags=["payments"])
app.include_router(payment_paypal.router, prefix="/api/payments", tags=["payments"])
app.include_router(contact.router, prefix="/api/contact", tags=["contact"])


@app.get("/api/health")
def healthcheck():
    return {"status": "ok", "service": "securewave-vpn"}


@app.get("/api/ready")
def readiness():
    try:
        db = SessionLocal()
        db.execute(text("SELECT 1"))
        db.close()
        return {"status": "ready", "database": "connected"}
    except Exception as e:
        return {"status": "not_ready", "error": str(e)}


static_directory = Path(__file__).resolve().parent / "static"

# Serve individual HTML pages from root
html_pages = [
    "index.html", "home.html", "login.html", "register.html",
    "dashboard.html", "vpn.html", "services.html", "subscription.html",
    "about.html", "contact.html", "privacy.html", "terms.html"
]

for page in html_pages:
    page_path = static_directory / page
    if page_path.exists():
        # Create route for each HTML page
        def make_page_handler(filepath):
            async def handler():
                return FileResponse(filepath)
            return handler

        route_path = f"/{page}"
        app.get(route_path, include_in_schema=False)(make_page_handler(page_path))

# Mount static assets (CSS, JS, images, etc.) under /static and root
if static_directory.exists():
    app.mount("/static", StaticFiles(directory=str(static_directory)), name="static")
    # Also mount at root for assets referenced as /css/style.css, /js/script.js, etc.
    app.mount("/css", StaticFiles(directory=str(static_directory / "css")), name="css")
    app.mount("/js", StaticFiles(directory=str(static_directory / "js")), name="js")
    app.mount("/img", StaticFiles(directory=str(static_directory / "img")), name="img")
    app.mount("/assets", StaticFiles(directory=str(static_directory / "assets")), name="assets")


@app.get("/", include_in_schema=False)
async def root():
    index_file = static_directory / "index.html"
    if index_file.exists():
        return FileResponse(index_file)
    return {"message": "SecureWave VPN API", "docs": "/api/docs"}


if __name__ == "__main__":
    import uvicorn

    # Optimized for VM resource usage
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", 8000)),
        reload=os.getenv("ENVIRONMENT") != "production",
        workers=1,  # Single worker for dev/low-resource VMs
        log_level="info",
        access_log=True,
        use_colors=True,
        limit_concurrency=100,  # Limit concurrent connections
        limit_max_requests=1000,  # Restart worker after N requests to prevent memory leaks
        timeout_keep_alive=5,  # Close idle connections faster
    )

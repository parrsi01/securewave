import os
import shutil
from pathlib import Path

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text

from database import base  # noqa: F401 - ensures models are registered
from database.session import SessionLocal, engine
from routers import auth, dashboard, optimizer, payment_paypal, payment_stripe, vpn
from services.wireguard_service import WireGuardService

base.Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="SecureWave VPN",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json",
)

origins_env = os.getenv("CORS_ORIGINS", "*")
origins = [o.strip() for o in origins_env.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins or ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


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
    sync_static_assets()
    app.state.wireguard = WireGuardService()


app.include_router(auth.router, prefix="/api/auth", tags=["auth"])
app.include_router(vpn.router, prefix="/api/vpn", tags=["vpn"])
app.include_router(optimizer.router, prefix="/api/optimizer", tags=["optimizer"])
app.include_router(dashboard.router, prefix="/api/dashboard", tags=["dashboard"])
app.include_router(payment_stripe.router, prefix="/api/payments", tags=["payments"])
app.include_router(payment_paypal.router, prefix="/api/payments", tags=["payments"])


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
if static_directory.exists():
    app.mount("/static", StaticFiles(directory=str(static_directory)), name="static")


@app.get("/", include_in_schema=False)
async def root():
    index_file = static_directory / "index.html"
    if index_file.exists():
        return FileResponse(index_file)
    return {"message": "SecureWave VPN API", "docs": "/api/docs"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=int(os.getenv("PORT", 8000)), reload=True)

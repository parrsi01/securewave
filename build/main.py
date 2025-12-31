import os
import shutil
from pathlib import Path

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from database import base  # noqa: F401 - ensures models are registered
from database.session import SessionLocal, engine
from routers import auth, dashboard, payment_paypal, payment_stripe, vpn
from services.wireguard_service import WireGuardService

base.Base.metadata.create_all(bind=engine)

app = FastAPI(title="SecureWave VPN", version="1.0.0")

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


app.include_router(auth.router, prefix="/auth", tags=["auth"])
app.include_router(vpn.router, prefix="/vpn", tags=["vpn"])
app.include_router(dashboard.router, prefix="/dashboard", tags=["dashboard"])
app.include_router(payment_stripe.router, prefix="/payments", tags=["payments"])
app.include_router(payment_paypal.router, prefix="/payments", tags=["payments"])

static_directory = Path(__file__).resolve().parent / "static"
app.mount("/static", StaticFiles(directory="static"), name="static")


@app.get("/", include_in_schema=False)
def root():
    return FileResponse(os.path.join("static", "index.html"))


app.mount("/", StaticFiles(directory=static_directory, html=True), name="static_root")


@app.get("/health")
def healthcheck():
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=int(os.getenv("PORT", 8000)), reload=True)

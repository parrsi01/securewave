"""
Test version of main.py - minimal with health check
"""
import os
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title="SecureWave VPN",
    version="1.0.0",
    docs_url="/api/docs",
)

# CORS Configuration
origins = [
    "https://securewave-web.azurewebsites.net",
    "https://www.securewave-web.azurewebsites.net",
    "http://localhost:3000",
    "http://localhost:8000"
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-CSRF-Token"],
    max_age=3600,
)

@app.get("/api/health")
def healthcheck():
    return {"status": "ok", "service": "securewave-vpn", "mode": "test"}

@app.get("/")
async def root():
    return {"message": "SecureWave VPN API - Test Mode", "docs": "/api/docs"}

# Try importing database
try:
    from database.session import SessionLocal
    from sqlalchemy import text

    @app.get("/api/ready")
    def readiness():
        try:
            db = SessionLocal()
            db.execute(text("SELECT 1"))
            db.close()
            return {"status": "ready", "database": "connected"}
        except Exception as e:
            return {"status": "not_ready", "error": str(e)}
except ImportError as e:
    @app.get("/api/ready")
    def readiness():
        return {"status": "no_db", "error": str(e)}

# Try importing models
try:
    from models import user, subscription, audit_log, vpn_server, vpn_connection
    @app.get("/api/models-status")
    def models_status():
        return {"models": "loaded"}
except ImportError as e:
    @app.get("/api/models-status")
    def models_status():
        return {"models": "failed", "error": str(e)}

# Try importing routers
try:
    from routers import auth, vpn, dashboard
    app.include_router(vpn.router, prefix="/api/vpn", tags=["vpn"])
    app.include_router(dashboard.router, prefix="/api/dashboard", tags=["dashboard"])
except ImportError as e:
    @app.get("/api/routers-status")
    def routers_status():
        return {"routers": "failed", "error": str(e)}

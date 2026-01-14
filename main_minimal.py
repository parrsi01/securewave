"""
Minimal version of main.py to test if FastAPI can start at all
"""
import os
from pathlib import Path
from fastapi import FastAPI

app = FastAPI(
    title="SecureWave VPN",
    version="1.0.0",
    docs_url="/api/docs",
)


@app.get("/api/health")
def healthcheck():
    return {"status": "ok", "service": "securewave-vpn", "mode": "minimal"}


@app.get("/")
async def root():
    return {"message": "SecureWave VPN API - Minimal Mode", "docs": "/api/docs"}

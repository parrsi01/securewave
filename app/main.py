from fastapi import FastAPI

from app.core import config
from app.core.logging import setup_logging
from app.core.observability import request_logging_middleware
from app.api import auth, users, devices, subscriptions, vpn

setup_logging()

app = FastAPI(title=config.PROJECT_NAME)
app.middleware("http")(request_logging_middleware)

app.include_router(auth.router, prefix=config.API_PREFIX)
app.include_router(users.router, prefix=config.API_PREFIX)
app.include_router(devices.router, prefix=config.API_PREFIX)
app.include_router(subscriptions.router, prefix=config.API_PREFIX)
app.include_router(vpn.router, prefix=config.API_PREFIX)


@app.get("/health")
def health_check():
    return {"status": "ok"}

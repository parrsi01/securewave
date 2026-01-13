#!/usr/bin/env bash
set -euo pipefail

export PYTHONPATH=.
python - <<'PY'
from app.db.base import Base
from app.db.session import engine
from app.models.user import User  # noqa: F401
from app.models.device import Device  # noqa: F401
from app.models.subscription import Subscription  # noqa: F401
from app.models.audit_log import AuditLog  # noqa: F401
from app.models.vpn_server import VPNServer  # noqa: F401

Base.metadata.create_all(bind=engine)
print("Database initialized")
PY

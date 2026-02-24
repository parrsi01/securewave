"""
Fake WireGuard management API used by local operational simulations.

Why:
- The real SecureWave backend integrates with remote WireGuard nodes via HTTP API or SSH.
- Local sandbox runs should avoid external dependencies while still exercising:
  - peer registration calls (add/remove)
  - health probes (list peers, server health)
  - handshake latency tracking (backend measures request duration)

This app intentionally implements only the endpoints expected by:
`services/wireguard_server_manager.py` (HTTP API mode):
  - POST /peers/add
  - POST /peers/remove
  - GET  /peers
  - GET  /status
  - GET  /health
"""

from __future__ import annotations

import asyncio
import hashlib
import os
import random
import time
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel


def _env_int(name: str, default: int) -> int:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return int(raw.strip())
    except ValueError:
        return default


def _env_float(name: str, default: float) -> float:
    raw = os.getenv(name)
    if raw is None:
        return default
    try:
        return float(raw.strip())
    except ValueError:
        return default


def _bucket_0_99(value: str) -> int:
    digest = hashlib.sha256(value.encode("utf-8")).hexdigest()
    return int(digest[:2], 16) % 100


class AddPeerRequest(BaseModel):
    public_key: str
    allowed_ips: str


class RemovePeerRequest(BaseModel):
    public_key: str


app = FastAPI(title="Fake WireGuard API", version="0.1")

_EXPECTED_API_KEY = os.getenv("WG_API_KEY", "").strip()
_SEED = _env_int("FAKE_WG_SEED", 1337)
_rng = random.Random(_SEED)

# Handshake freshness controls (used by SecureWave's VPNHealthMonitor).
_STALE_UNSTABLE_PCT = max(0, min(100, _env_int("FAKE_WG_STALE_UNSTABLE_PCT", 5)))
_STALE_DEGRADED_PCT = max(0, min(100, _env_int("FAKE_WG_STALE_DEGRADED_PCT", 15)))

# Degraded behavior controls (sleep + occasional failures).
_ADD_FAIL_PCT = max(0.0, min(100.0, _env_float("FAKE_WG_ADD_FAIL_PCT", 1.0)))
_LIST_FAIL_PCT = max(0.0, min(100.0, _env_float("FAKE_WG_LIST_FAIL_PCT", 0.5)))
_REMOVE_FAIL_PCT = max(0.0, min(100.0, _env_float("FAKE_WG_REMOVE_FAIL_PCT", 0.2)))

_ADD_P95_DELAY_MS = max(0, _env_int("FAKE_WG_ADD_P95_DELAY_MS", 450))
_LIST_P95_DELAY_MS = max(0, _env_int("FAKE_WG_LIST_P95_DELAY_MS", 250))
_BASE_DELAY_MS = max(0, _env_int("FAKE_WG_BASE_DELAY_MS", 25))

# Minimal in-memory "peer registry"
_lock = asyncio.Lock()
_peers: Dict[str, Dict[str, Any]] = {}


def _require_key(x_api_key: Optional[str]) -> None:
    # In sandbox, allow missing expected key (avoids surprises), but still enforce
    # if WG_API_KEY is configured.
    if not _EXPECTED_API_KEY:
        return
    if (x_api_key or "").strip() != _EXPECTED_API_KEY:
        raise HTTPException(status_code=401, detail="invalid api key")


async def _maybe_delay(kind: str) -> None:
    # Delay distribution: mostly low, occasional p95-ish spikes.
    p = _rng.random() * 100.0
    if kind == "add":
        p95 = _ADD_P95_DELAY_MS
    elif kind == "list":
        p95 = _LIST_P95_DELAY_MS
    else:
        p95 = int((_ADD_P95_DELAY_MS + _LIST_P95_DELAY_MS) / 2)

    if p < 90.0:
        delay_ms = _BASE_DELAY_MS + _rng.randint(0, int(max(1, p95 * 0.15)))
    elif p < 98.0:
        delay_ms = int(p95 * 0.4) + _rng.randint(0, int(max(1, p95 * 0.7)))
    else:
        delay_ms = int(p95 * 1.5) + _rng.randint(0, int(max(1, p95 * 2.0)))

    await asyncio.sleep(delay_ms / 1000.0)


def _maybe_fail(pct: float) -> bool:
    return (_rng.random() * 100.0) < pct


@app.get("/health")
async def health(x_api_key: Optional[str] = Header(default=None, alias="X-API-Key")) -> Dict[str, Any]:
    _require_key(x_api_key)
    return {"healthy": True, "mode": "fake", "peers": len(_peers)}


@app.get("/status")
async def status(x_api_key: Optional[str] = Header(default=None, alias="X-API-Key")) -> Dict[str, Any]:
    _require_key(x_api_key)
    async with _lock:
        peers = len(_peers)
    return {"status": "ok", "peers": peers, "seed": _SEED}


@app.post("/peers/add")
async def add_peer(
    payload: AddPeerRequest,
    x_api_key: Optional[str] = Header(default=None, alias="X-API-Key"),
) -> Dict[str, Any]:
    _require_key(x_api_key)
    await _maybe_delay("add")
    if _maybe_fail(_ADD_FAIL_PCT):
        return {"success": False, "error": "simulated_add_failure"}

    now = int(time.time())
    async with _lock:
        entry = _peers.get(payload.public_key) or {}
        entry.update(
            {
                "public_key": payload.public_key,
                "allowed_ips": payload.allowed_ips,
                "created_at": entry.get("created_at") or now,
                "latest_handshake": now,
                "transfer_rx": int(entry.get("transfer_rx") or 0),
                "transfer_tx": int(entry.get("transfer_tx") or 0),
            }
        )
        _peers[payload.public_key] = entry
    return {"success": True, "message": "peer added"}


@app.post("/peers/remove")
async def remove_peer(
    payload: RemovePeerRequest,
    x_api_key: Optional[str] = Header(default=None, alias="X-API-Key"),
) -> Dict[str, Any]:
    _require_key(x_api_key)
    await _maybe_delay("remove")
    if _maybe_fail(_REMOVE_FAIL_PCT):
        return {"success": False, "error": "simulated_remove_failure"}

    async with _lock:
        existed = payload.public_key in _peers
        _peers.pop(payload.public_key, None)
    return {"success": True, "message": "peer removed", "existed": existed}


@app.get("/peers")
async def list_peers(x_api_key: Optional[str] = Header(default=None, alias="X-API-Key")) -> List[Dict[str, Any]]:
    _require_key(x_api_key)
    await _maybe_delay("list")
    if _maybe_fail(_LIST_FAIL_PCT):
        raise HTTPException(status_code=503, detail="simulated_list_failure")

    now = int(time.time())
    degraded_cutoff = int(os.getenv("WG_HANDSHAKE_DEGRADED_SECONDS", "120") or "120")
    unstable_cutoff = int(os.getenv("WG_HANDSHAKE_UNSTABLE_SECONDS", "300") or "300")

    async with _lock:
        peers = list(_peers.values())

    out: List[Dict[str, Any]] = []
    for entry in peers:
        pk = str(entry.get("public_key") or "")
        bucket = _bucket_0_99(pk)
        latest = int(entry.get("latest_handshake") or now)

        # Force a deterministic fraction of peers into stale buckets to exercise
        # health classification (healthy/degraded/unstable).
        if bucket < _STALE_UNSTABLE_PCT:
            latest = now - unstable_cutoff - 15
        elif bucket < (_STALE_UNSTABLE_PCT + _STALE_DEGRADED_PCT):
            latest = now - degraded_cutoff - 15

        # Best-effort transfer drift.
        rx = int(entry.get("transfer_rx") or 0) + _rng.randint(0, 4096)
        tx = int(entry.get("transfer_tx") or 0) + _rng.randint(0, 4096)

        out.append(
            {
                "public_key": pk,
                "allowed_ips": entry.get("allowed_ips"),
                "latest_handshake": latest,
                "transfer_rx": rx,
                "transfer_tx": tx,
            }
        )

    # Persist transfer drift.
    async with _lock:
        for item in out:
            pk = item.get("public_key")
            if pk and pk in _peers:
                _peers[pk]["transfer_rx"] = int(item.get("transfer_rx") or 0)
                _peers[pk]["transfer_tx"] = int(item.get("transfer_tx") or 0)

    return out


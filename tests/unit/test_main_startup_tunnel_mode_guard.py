from __future__ import annotations

import pytest

from main import app, lifespan


@pytest.mark.anyio
async def test_startup_fails_when_tunnel_mode_guard_raises(monkeypatch):
    monkeypatch.setenv("TESTING", "true")

    def _explode():
        raise RuntimeError("sim mode forbidden")

    monkeypatch.setattr("main.ensure_tunnel_mode_allowed", _explode)

    with pytest.raises(RuntimeError, match="sim mode forbidden"):
        async with lifespan(app):
            pass

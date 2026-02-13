"""
In-process ASGI test client without background threads.

Why:
- The sandbox environment forbids socket sends, which breaks asyncio's
  `call_soon_threadsafe()` wakeups used by Starlette/FastAPI's TestClient.
- This client runs the app and HTTP requests in a single event loop thread.

This is a minimal drop-in for the subset of `fastapi.testclient.TestClient`
APIs used by this repo's tests/harnesses (get/post/etc + context manager).
"""

from __future__ import annotations

import asyncio
import os
from typing import Any, Optional

import httpx


class InProcessTestClient:
    def __init__(
        self,
        app,
        *,
        base_url: str = "http://testserver",
        raise_server_exceptions: bool = True,
    ) -> None:
        self.app = app
        self.base_url = base_url
        self.raise_server_exceptions = raise_server_exceptions
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._client: Optional[httpx.AsyncClient] = None
        self._lifespan_cm = None
        self._orig_anyio_run_sync = None

    def __enter__(self) -> "InProcessTestClient":
        self._loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self._loop)

        # In this sandbox, thread-to-loop wakeups are blocked, which breaks
        # AnyIO's threadpool offloading used for sync endpoints/dependencies.
        # For tests/harnesses we run sync callables inline instead.
        if os.getenv("TESTING", "").lower() == "true" or os.getenv("SECUREWAVE_DISABLE_THREADPOOL", "").lower() in {"1", "true", "yes", "on"}:
            import anyio.to_thread

            self._orig_anyio_run_sync = anyio.to_thread.run_sync

            async def _run_sync_inline(func, *args, **kwargs):
                kwargs.pop("abandon_on_cancel", None)
                kwargs.pop("cancellable", None)
                kwargs.pop("limiter", None)
                return func(*args)

            anyio.to_thread.run_sync = _run_sync_inline  # type: ignore[assignment]

        transport = httpx.ASGITransport(
            app=self.app,
            raise_app_exceptions=self.raise_server_exceptions,
        )
        # Align behavior with requests/Starlette TestClient:
        # - Persist cookies across requests
        # - Follow redirects by default (requests follows redirects on GETs)
        self._client = httpx.AsyncClient(
            transport=transport,
            base_url=self.base_url,
            follow_redirects=True,
        )

        # Run ASGI lifespan startup (mirrors Starlette TestClient behavior).
        if getattr(self.app, "router", None) and getattr(self.app.router, "lifespan_context", None):
            self._lifespan_cm = self.app.router.lifespan_context(self.app)
            self._loop.run_until_complete(self._lifespan_cm.__aenter__())

        return self

    @property
    def cookies(self) -> httpx.Cookies:
        assert self._client is not None, "Client must be used as a context manager"
        return self._client.cookies

    def __exit__(self, exc_type, exc, tb) -> None:
        assert self._loop is not None
        assert self._client is not None

        if self._lifespan_cm is not None:
            self._loop.run_until_complete(self._lifespan_cm.__aexit__(exc_type, exc, tb))

        self._loop.run_until_complete(self._client.aclose())
        self._loop.close()
        asyncio.set_event_loop(None)

        if self._orig_anyio_run_sync is not None:
            import anyio.to_thread

            anyio.to_thread.run_sync = self._orig_anyio_run_sync  # type: ignore[assignment]
            self._orig_anyio_run_sync = None

        self._loop = None
        self._client = None
        self._lifespan_cm = None

    def request(self, method: str, url: str, **kwargs: Any) -> httpx.Response:
        assert self._loop is not None, "Client must be used as a context manager"
        assert self._client is not None, "Client must be used as a context manager"
        return self._loop.run_until_complete(self._client.request(method, url, **kwargs))

    def get(self, url: str, **kwargs: Any) -> httpx.Response:
        return self.request("GET", url, **kwargs)

    def post(self, url: str, **kwargs: Any) -> httpx.Response:
        return self.request("POST", url, **kwargs)

    def put(self, url: str, **kwargs: Any) -> httpx.Response:
        return self.request("PUT", url, **kwargs)

    def patch(self, url: str, **kwargs: Any) -> httpx.Response:
        return self.request("PATCH", url, **kwargs)

    def delete(self, url: str, **kwargs: Any) -> httpx.Response:
        return self.request("DELETE", url, **kwargs)

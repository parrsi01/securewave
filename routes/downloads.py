"""
Download routes for SecureWave VPN client applications.

Provides:
- GET /api/downloads       - Available downloads with platform detection
- GET /api/downloads/list  - Alias for the above
- GET /api/downloads/detect - Auto-detect user platform from User-Agent
- GET /api/downloads/file/{filename} - Serve a specific download file
"""

import os
import logging
from pathlib import Path
from typing import Optional, List

from fastapi import APIRouter, Request, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/downloads", tags=["downloads"])

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
DOWNLOADS_DIR = Path(__file__).resolve().parent.parent / "static" / "downloads"


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class DownloadEntry(BaseModel):
    platform: str
    architecture: str
    filename: str
    url: str
    version: str
    size_bytes: Optional[int] = None
    size_display: Optional[str] = None
    status: str  # "available" | "coming_soon"
    notes: Optional[str] = None


class DownloadListResponse(BaseModel):
    version: str
    detected_platform: Optional[str] = None
    downloads: List[DownloadEntry]


class PlatformDetectResponse(BaseModel):
    platform: str
    architecture: str
    recommended_download: Optional[str] = None


# ---------------------------------------------------------------------------
# Platform detection from User-Agent
# ---------------------------------------------------------------------------

def detect_platform(user_agent: str) -> dict:
    """Parse User-Agent to determine platform and architecture."""
    ua = user_agent.lower()

    if "windows" in ua:
        arch = "arm64" if "arm64" in ua or "aarch64" in ua else "x64"
        return {"platform": "windows", "architecture": arch}

    if "iphone" in ua or "ipad" in ua:
        return {"platform": "ios", "architecture": "arm64"}
    if "macintosh" in ua or "mac os" in ua:
        arch = "arm64" if "arm64" in ua else "x64"
        return {"platform": "macos", "architecture": arch}

    if "android" in ua:
        arch = "arm64" if "arm64" in ua or "aarch64" in ua else "universal"
        return {"platform": "android", "architecture": arch}

    if "linux" in ua:
        arch = "arm64" if "aarch64" in ua or "arm64" in ua else "x64"
        return {"platform": "linux", "architecture": arch}

    return {"platform": "unknown", "architecture": "unknown"}


def _format_size(size_bytes: int) -> str:
    """Format byte count into human-readable string."""
    if size_bytes < 1024:
        return f"{size_bytes} B"
    elif size_bytes < 1024 * 1024:
        return f"{size_bytes / 1024:.1f} KB"
    elif size_bytes < 1024 * 1024 * 1024:
        return f"{size_bytes / (1024 * 1024):.1f} MB"
    else:
        return f"{size_bytes / (1024 * 1024 * 1024):.2f} GB"


# ---------------------------------------------------------------------------
# Download manifest -- canonical list of all platform builds
# ---------------------------------------------------------------------------

DOWNLOAD_MANIFEST = [
    # Windows
    {
        "platform": "windows",
        "architecture": "x64",
        "filename": "securewave-windows-x64-setup.exe",
        "url": "/downloads/securewave-windows-x64-setup.exe",
        "notes": "Windows 10+. NSIS installer (may be unsigned in early builds).",
    },
    # Linux
    {
        "platform": "linux",
        "architecture": "x64",
        "filename": "securewave-linux-x64.deb",
        "url": "/downloads/securewave-linux-x64.deb",
        "notes": "Debian/Ubuntu package (coming soon).",
    },
    {
        "platform": "linux",
        "architecture": "x64",
        "filename": "securewave-linux-x64.AppImage",
        "url": "/downloads/securewave-linux-x64.AppImage",
        "notes": "Portable AppImage build (coming soon).",
    },
    {
        "platform": "linux",
        "architecture": "x64",
        "filename": "securewave-linux-x64.tar.gz",
        "url": "/downloads/securewave-linux-x64.tar.gz",
        "notes": "Portable tarball (x64).",
    },
    {
        "platform": "linux",
        "architecture": "arm64",
        "filename": "securewave-app-linux-arm64.zip",
        "url": "/downloads/securewave-app-linux-arm64.zip",
        "notes": "Portable zip (ARM64).",
    },
    # Apple
    {
        "platform": "macos",
        "architecture": "arm64",
        "filename": "securewave-macos-arm64.dmg",
        "url": "#",
        "notes": "Coming soon. Requires Apple Developer signing and notarization.",
    },
    {
        "platform": "ios",
        "architecture": "arm64",
        "filename": "",
        "url": "#",
        "notes": "Coming soon. Will be available on the Apple App Store / TestFlight.",
    },
    # Android
    {
        "platform": "android",
        "architecture": "universal",
        "filename": "securewave-android.apk",
        "url": "/downloads/securewave-android.apk",
        "notes": "Android 10+. APK link appears here when published.",
    },
]


def _build_download_entries() -> List[DownloadEntry]:
    """Build download list, checking which files actually exist on disk."""
    entries = []
    for item in DOWNLOAD_MANIFEST:
        filename = item["filename"]

        # Check if the file actually exists on disk
        file_exists = False
        size_bytes = None
        size_display = None

        if filename:
            file_path = DOWNLOADS_DIR / filename
            file_exists = file_path.exists()
            if file_exists:
                size_bytes = file_path.stat().st_size
                size_display = _format_size(size_bytes)

        status = "available" if file_exists else "coming_soon"

        entries.append(DownloadEntry(
            platform=item["platform"],
            architecture=item["architecture"],
            filename=filename,
            url=item["url"] if file_exists or item["url"] == "#" else "#",
            version=APP_VERSION,
            size_bytes=size_bytes,
            size_display=size_display,
            status=status,
            notes=item["notes"],
        ))

    return entries


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.get("", response_model=DownloadListResponse)
@router.get("/list", response_model=DownloadListResponse)
async def list_downloads(request: Request):
    """Return all available downloads with platform auto-detection."""
    user_agent = request.headers.get("user-agent", "")
    detected = detect_platform(user_agent)
    entries = _build_download_entries()
    return DownloadListResponse(
        version=APP_VERSION,
        detected_platform=detected["platform"],
        downloads=entries,
    )


@router.get("/detect", response_model=PlatformDetectResponse)
async def detect_user_platform(request: Request):
    """Auto-detect the user platform and recommend the best download."""
    user_agent = request.headers.get("user-agent", "")
    detected = detect_platform(user_agent)

    recommended = None
    for item in DOWNLOAD_MANIFEST:
        if item["platform"] == detected["platform"]:
            if item["architecture"] in (detected["architecture"], "universal"):
                if item["filename"]:
                    file_path = DOWNLOADS_DIR / item["filename"]
                    if file_path.exists():
                        recommended = item["url"]
                        break

    return PlatformDetectResponse(
        platform=detected["platform"],
        architecture=detected["architecture"],
        recommended_download=recommended,
    )


@router.get("/file/{filename}")
async def serve_download(filename: str):
    """
    Serve a download file with Content-Disposition attachment header.
    This is a fallback route; normally /downloads/{filename} is served
    by the StaticFiles mount in main.py.
    """
    # Sanitize: only allow the basename, reject path traversal
    safe_name = Path(filename).name
    if safe_name != filename or ".." in filename:
        raise HTTPException(status_code=400, detail="Invalid filename")

    file_path = DOWNLOADS_DIR / safe_name
    if not file_path.exists():
        raise HTTPException(
            status_code=404,
            detail=f"Download '{safe_name}' not found. It may not have been built yet.",
        )

    return FileResponse(
        path=str(file_path),
        filename=safe_name,
        media_type="application/octet-stream",
        headers={"Content-Disposition": f'attachment; filename="{safe_name}"'},
    )

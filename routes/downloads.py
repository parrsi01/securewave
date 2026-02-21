"""
Download routes for SecureWave VPN client applications.

Manifest source of truth:
- static/downloads/version.json

Provides:
- GET /api/downloads          - Manifest-backed downloads with platform detection
- GET /api/downloads/list     - Alias for /api/downloads
- GET /api/downloads/detect   - Auto-detect user platform and recommend a live artifact
- GET /api/downloads/manifest - Return parsed manifest with availability resolution
- GET /api/downloads/file/{filename} - Serve a specific download file
"""

from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/downloads", tags=["downloads"])


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

def _load_version_file() -> str:
    version_path = Path(__file__).resolve().parent.parent / "VERSION"
    try:
        version = version_path.read_text(encoding="utf-8").strip()
    except OSError:
        return "1.0.0"
    return version or "1.0.0"


APP_VERSION = os.getenv("APP_VERSION") or _load_version_file()
DOWNLOADS_DIR = Path(__file__).resolve().parent.parent / "static" / "downloads"
MANIFEST_PATH = Path(
    os.getenv("SECUREWAVE_RELEASE_MANIFEST_PATH") or DOWNLOADS_DIR / "version.json"
)


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class DownloadEntry(BaseModel):
    platform: str
    architecture: str
    filename: str = ""
    url: Optional[str] = None
    version: str
    format: Optional[str] = None
    build_date: Optional[str] = None
    size_bytes: Optional[int] = None
    size_display: Optional[str] = None
    checksum_sha256: Optional[str] = None
    signed: Optional[bool] = None
    signing_notes: Optional[str] = None
    primary: bool = False
    status: str  # "available" | "unavailable"
    notes: Optional[str] = None


class DownloadListResponse(BaseModel):
    version: str
    build_date: Optional[str] = None
    detected_platform: Optional[str] = None
    downloads: List[DownloadEntry]


class PlatformDetectResponse(BaseModel):
    platform: str
    architecture: str
    recommended_download: Optional[str] = None


class ReleaseManifestResponse(BaseModel):
    version: str
    build_date: Optional[str] = None
    generated_at: Optional[str] = None
    provider: Optional[str] = None
    artifacts: List[DownloadEntry]


# ---------------------------------------------------------------------------
# Platform detection from User-Agent
# ---------------------------------------------------------------------------

def detect_platform(user_agent: str) -> Dict[str, str]:
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
    if size_bytes < 1024 * 1024:
        return f"{size_bytes / 1024:.1f} KB"
    if size_bytes < 1024 * 1024 * 1024:
        return f"{size_bytes / (1024 * 1024):.1f} MB"
    return f"{size_bytes / (1024 * 1024 * 1024):.2f} GB"


# ---------------------------------------------------------------------------
# Manifest loading and availability resolution
# ---------------------------------------------------------------------------

def _empty_manifest() -> Dict[str, Any]:
    return {
        "version": APP_VERSION,
        "build_date": None,
        "generated_at": None,
        "provider": "hetzner",
        "artifacts": [],
    }


def _load_release_manifest() -> Dict[str, Any]:
    if not MANIFEST_PATH.exists():
        logger.warning("release manifest missing: %s", MANIFEST_PATH)
        return _empty_manifest()

    try:
        raw = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        logger.error("failed to parse release manifest %s: %s", MANIFEST_PATH, exc)
        return _empty_manifest()

    artifacts = raw.get("artifacts")
    if not isinstance(artifacts, list):
        artifacts = []

    provider = str(raw.get("provider") or "hetzner")
    if provider.lower() != "hetzner":
        logger.warning("unexpected provider in release manifest: %s", provider)

    return {
        "version": str(raw.get("version") or APP_VERSION),
        "build_date": raw.get("build_date"),
        "generated_at": raw.get("generated_at"),
        "provider": provider,
        "artifacts": artifacts,
    }


def _artifact_is_local(url: Optional[str]) -> bool:
    return bool(url and isinstance(url, str) and url.startswith("/downloads/"))


def _resolve_availability(item: Dict[str, Any], filename: str, url: Optional[str]) -> Dict[str, Any]:
    declared_status = str(item.get("status") or "available").strip().lower()
    declared_available = declared_status == "available"
    notes = str(item.get("notes") or "").strip() or None

    size_bytes: Optional[int] = item.get("size_bytes")

    if not declared_available:
        return {
            "available": False,
            "size_bytes": size_bytes,
            "notes": notes,
        }

    if _artifact_is_local(url):
        local_name = filename or Path(url).name
        if not local_name:
            return {
                "available": False,
                "size_bytes": size_bytes,
                "notes": notes or "Manifest entry has no filename for a local download URL.",
            }

        file_path = DOWNLOADS_DIR / local_name
        if not file_path.exists() or not file_path.is_file():
            return {
                "available": False,
                "size_bytes": size_bytes,
                "notes": notes or "Artifact not present on this host.",
            }

        resolved_size = file_path.stat().st_size
        return {
            "available": True,
            "size_bytes": resolved_size,
            "notes": notes,
        }

    # External URL path (e.g., App Store/TestFlight) may still be available.
    if isinstance(url, str) and url.startswith(("https://", "http://")):
        return {
            "available": True,
            "size_bytes": size_bytes,
            "notes": notes,
        }

    return {
        "available": False,
        "size_bytes": size_bytes,
        "notes": notes or "No download URL published.",
    }


def _build_download_entries(manifest: Dict[str, Any]) -> List[DownloadEntry]:
    entries: List[DownloadEntry] = []

    for item in manifest.get("artifacts", []):
        if not isinstance(item, dict):
            continue

        platform = str(item.get("platform") or "unknown")
        architecture = str(item.get("architecture") or "unknown")
        filename = str(item.get("filename") or "")
        url = item.get("url")
        url = str(url) if isinstance(url, str) and url.strip() else None

        resolved = _resolve_availability(item, filename, url)
        available = bool(resolved["available"])
        size_bytes = resolved["size_bytes"]
        size_display = _format_size(size_bytes) if isinstance(size_bytes, int) else None

        status = "available" if available else "unavailable"
        effective_url = url if available else None

        entries.append(
            DownloadEntry(
                platform=platform,
                architecture=architecture,
                filename=filename,
                url=effective_url,
                version=str(item.get("version") or manifest.get("version") or APP_VERSION),
                format=item.get("format"),
                build_date=item.get("build_date") or manifest.get("build_date"),
                size_bytes=size_bytes,
                size_display=size_display,
                checksum_sha256=item.get("sha256") or item.get("checksum_sha256"),
                signed=item.get("signed"),
                signing_notes=item.get("signing_notes"),
                primary=bool(item.get("primary", False)),
                status=status,
                notes=resolved.get("notes"),
            )
        )

    return entries


def _pick_recommended_download(
    entries: List[DownloadEntry],
    detected_platform: str,
    detected_architecture: str,
) -> Optional[str]:
    candidates = [
        entry
        for entry in entries
        if entry.status == "available"
        and entry.platform == detected_platform
        and entry.url
        and entry.architecture in (detected_architecture, "universal")
    ]

    if not candidates:
        candidates = [
            entry
            for entry in entries
            if entry.status == "available"
            and entry.platform == detected_platform
            and entry.url
        ]

    if not candidates:
        return None

    candidates.sort(
        key=lambda entry: (
            0 if entry.primary else 1,
            0 if entry.architecture == detected_architecture else 1,
            entry.architecture,
        )
    )
    return candidates[0].url


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.get("", response_model=DownloadListResponse)
@router.get("/list", response_model=DownloadListResponse)
async def list_downloads(request: Request):
    """Return all manifest-backed downloads with platform auto-detection."""
    user_agent = request.headers.get("user-agent", "")
    detected = detect_platform(user_agent)

    manifest = _load_release_manifest()
    entries = _build_download_entries(manifest)

    return DownloadListResponse(
        version=str(manifest.get("version") or APP_VERSION),
        build_date=manifest.get("build_date"),
        detected_platform=detected["platform"],
        downloads=entries,
    )


@router.get("/manifest", response_model=ReleaseManifestResponse)
async def get_release_manifest():
    """Return parsed release manifest with resolved availability status."""
    manifest = _load_release_manifest()
    entries = _build_download_entries(manifest)

    return ReleaseManifestResponse(
        version=str(manifest.get("version") or APP_VERSION),
        build_date=manifest.get("build_date"),
        generated_at=manifest.get("generated_at"),
        provider=manifest.get("provider"),
        artifacts=entries,
    )


@router.get("/detect", response_model=PlatformDetectResponse)
async def detect_user_platform(request: Request):
    """Auto-detect the user platform and recommend the best published download."""
    user_agent = request.headers.get("user-agent", "")
    detected = detect_platform(user_agent)

    manifest = _load_release_manifest()
    entries = _build_download_entries(manifest)
    recommended = _pick_recommended_download(
        entries,
        detected_platform=detected["platform"],
        detected_architecture=detected["architecture"],
    )

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
    safe_name = Path(filename).name
    if safe_name != filename or ".." in filename:
        raise HTTPException(status_code=400, detail="Invalid filename")

    file_path = DOWNLOADS_DIR / safe_name
    if not file_path.exists() or not file_path.is_file():
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

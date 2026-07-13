"""
Download routes for SecureWave VPN client applications.

Provides:
- GET /api/downloads       - Available downloads with platform detection
- GET /api/downloads/list  - Alias for the above
- GET /api/downloads/detect - Auto-detect user platform from User-Agent
- GET /api/downloads/file/{filename} - Serve a specific download file
"""

from collections import Counter
import hashlib
import json
import logging
import os
from pathlib import Path
from typing import List, Literal, Optional

from fastapi import APIRouter, Request, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel, ConfigDict, ValidationError, field_validator, model_validator

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/downloads", tags=["downloads"])
# Preserve the long-standing public /downloads URLs while routing them through
# the same manifest and integrity checks as the API endpoint.
public_router = APIRouter(tags=["downloads"])

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
DOWNLOADS_DIR = Path(__file__).resolve().parent.parent / "static" / "downloads"
DOWNLOAD_MANIFEST_PATH = DOWNLOADS_DIR / "manifest.json"


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
    status: str  # "available" | "beta" | "coming_soon"
    notes: Optional[str] = None
    checksum_sha256: Optional[str] = None
    evidence_url: Optional[str] = None
    evidence_label: Optional[str] = None


DownloadStatus = Literal["available", "beta", "coming_soon"]


class DownloadManifestEntry(BaseModel):
    """Strict internal schema for one manifest row."""

    model_config = ConfigDict(extra="forbid", strict=True)

    platform: str
    architecture: str
    filename: str
    url: str
    status: DownloadStatus
    notes: str
    checksum_sha256: Optional[str] = None
    evidence_url: Optional[str] = None
    evidence_label: Optional[str] = None

    @field_validator("platform", "architecture", "url", "notes")
    @classmethod
    def validate_non_empty_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("must not be empty")
        return value

    @field_validator("filename")
    @classmethod
    def validate_filename(cls, value: str) -> str:
        if value != value.strip():
            raise ValueError("filename must not have surrounding whitespace")
        if value:
            if value in {".", ".."} or "/" in value or "\\" in value or "\x00" in value:
                raise ValueError("filename must be a basename")
            if Path(value).name != value:
                raise ValueError("filename must be a basename")
        return value

    @field_validator("checksum_sha256")
    @classmethod
    def validate_checksum(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        normalized = value.strip().lower()
        if len(normalized) != 64 or any(char not in "0123456789abcdef" for char in normalized):
            raise ValueError("checksum_sha256 must be 64 hexadecimal characters")
        return normalized

    @model_validator(mode="after")
    def validate_status_requirements(self):
        if self.status in {"available", "beta"} and not self.filename:
            raise ValueError(f"{self.status} downloads require a filename")
        if not (
            self.url == "#"
            or self.url.startswith("/downloads/")
            or self.url.startswith("https://")
        ):
            raise ValueError("download URLs must be guarded local paths or HTTPS links")
        if self.evidence_url and not self.evidence_url.startswith("https://"):
            raise ValueError("evidence_url must use HTTPS")
        if self.status == "available" and self.url != f"/downloads/{self.filename}":
            raise ValueError("available downloads must use the guarded public download URL")
        return self


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

DEFAULT_DOWNLOAD_MANIFEST = [
    # Apple handoff
    {
        "platform": "macos",
        "architecture": "universal",
        "filename": "securewave-apple-release-handoff.zip",
        "url": "/downloads/securewave-apple-release-handoff.zip",
        "status": "available",
        "notes": "Mac/Xcode handoff kit for producing the signed macOS/iOS archive. Not a notarized app bundle.",
    },
    {
        "platform": "macos",
        "architecture": "arm64",
        "filename": "securewave-macos-arm64-ui-demo.zip",
        "url": "/downloads/securewave-macos-arm64-ui-demo.zip",
        "status": "available",
        "notes": "macOS UI demo app package. Build this on an Apple Silicon Mac with securewave_app/scripts/package_macos_ui_demo.sh; VPN tunneling is not enabled in the macOS demo.",
    },
    {
        "platform": "macos",
        "architecture": "x64",
        "filename": "securewave-macos-x64-ui-demo.zip",
        "url": "/downloads/securewave-macos-x64-ui-demo.zip",
        "status": "coming_soon",
        "notes": "macOS UI demo app package. Build this on an Intel Mac with securewave_app/scripts/package_macos_ui_demo.sh; VPN tunneling is not enabled in the macOS demo.",
    },
    # Windows
    {
        "platform": "windows",
        "architecture": "x64",
        "filename": "securewave-windows-x64-setup.exe",
        "url": "/downloads/securewave-windows-x64-setup.exe",
        "status": "coming_soon",
        "notes": "Windows 10+. NSIS installer (may be unsigned in early builds).",
    },
    # Linux
    {
        "platform": "linux",
        "architecture": "x64",
        "filename": "securewave-linux-x64.deb",
        "url": "#",
        "status": "coming_soon",
        "evidence_url": "https://github.com/parrsi01/securewave/actions/runs/29261131617",
        "evidence_label": "GitHub Actions build evidence",
        "checksum_sha256": "c51616246415d405a45305d923332f989c0fa71c6b01ddc99ed86f3d0ea394c9",
        "notes": "GitHub Actions build evidence from the reviewed source head is available for an amd64 .deb with helper payload and dependency metadata. The package remains unpublished until clean x86_64 VM install, helper service, socket, uninstall, and live VPN runtime proof are complete.",
    },
    {
        "platform": "linux",
        "architecture": "x64",
        "filename": "securewave-linux-x64.AppImage",
        "url": "/downloads/securewave-linux-x64.AppImage",
        "status": "coming_soon",
        "notes": "Portable AppImage build (coming soon).",
    },
    {
        "platform": "linux",
        "architecture": "x64",
        "filename": "securewave-linux-x64.tar.gz",
        "url": "/downloads/securewave-linux-x64.tar.gz",
        "status": "available",
        "notes": "Portable tarball (x64).",
    },
    {
        "platform": "linux",
        "architecture": "arm64",
        "filename": "securewave-app-linux-arm64.zip",
        "url": "/downloads/securewave-app-linux-arm64.zip",
        "status": "available",
        "notes": "Portable zip (ARM64).",
    },
    # Apple
    {
        "platform": "ios",
        "architecture": "arm64",
        "filename": "",
        "url": "#",
        "status": "coming_soon",
        "notes": "Coming soon. Will be available on the Apple App Store / TestFlight.",
    },
    # Android
    {
        "platform": "android",
        "architecture": "universal",
        "filename": "securewave-android.apk",
        "url": "/downloads/securewave-android.apk",
        "status": "coming_soon",
        "notes": "Android 10+. APK link appears here when published.",
    },
]


def _validate_manifest_rows(rows: object, *, source: str) -> List[DownloadManifestEntry]:
    """Validate rows independently so one malformed entry cannot break the API."""
    if not isinstance(rows, list):
        logger.warning("Download manifest source=%s did not contain a downloads list", source)
        return []

    entries: List[DownloadManifestEntry] = []
    for index, row in enumerate(rows):
        try:
            entries.append(DownloadManifestEntry.model_validate(row))
        except ValidationError as exc:
            # Do not log the row or Pydantic's input values; manifests may be operator supplied.
            fields = sorted({".".join(str(part) for part in error["loc"]) for error in exc.errors()})
            logger.warning(
                "Skipping invalid download manifest row source=%s index=%s fields=%s",
                source,
                index,
                ",".join(fields) or "row",
            )

    filename_counts = Counter(entry.filename for entry in entries if entry.filename)
    duplicate_names = {filename for filename, count in filename_counts.items() if count > 1}
    if duplicate_names:
        logger.warning(
            "Skipping duplicate download manifest filenames source=%s count=%s",
            source,
            len(duplicate_names),
        )
        entries = [entry for entry in entries if entry.filename not in duplicate_names]

    return entries


def _default_manifest_entries() -> List[DownloadManifestEntry]:
    return _validate_manifest_rows(DEFAULT_DOWNLOAD_MANIFEST, source="built-in")


def _load_download_manifest() -> List[dict]:
    """Load validated public manifest rows, falling back on structural/read errors."""
    if not DOWNLOAD_MANIFEST_PATH.is_file():
        return [entry.model_dump() for entry in _default_manifest_entries()]
    try:
        payload = json.loads(DOWNLOAD_MANIFEST_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        logger.warning("Failed to read download manifest %s: %s", DOWNLOAD_MANIFEST_PATH, exc)
        return [entry.model_dump() for entry in _default_manifest_entries()]

    if not isinstance(payload, dict) or not isinstance(payload.get("downloads"), list):
        logger.warning("Download manifest had an invalid top-level structure")
        return [entry.model_dump() for entry in _default_manifest_entries()]

    entries = _validate_manifest_rows(payload["downloads"], source="file")
    return [entry.model_dump() for entry in entries]


def _safe_local_file(filename: str) -> Optional[Path]:
    """Return a contained regular file, rejecting traversal and symlink escapes."""
    if not filename:
        return None
    root = DOWNLOADS_DIR.resolve()
    candidate = DOWNLOADS_DIR / filename
    try:
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(root)
    except (OSError, ValueError):
        return None
    if candidate.is_symlink() or not resolved.is_file():
        return None
    return resolved


def _sha256_matches(file_path: Path, expected: str) -> bool:
    digest = hashlib.sha256()
    try:
        with file_path.open("rb") as file_handle:
            for chunk in iter(lambda: file_handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        logger.warning("Unable to verify download checksum filename=%s error=%s", file_path.name, exc)
        return False
    return digest.hexdigest() == expected


def _build_download_entries() -> List[DownloadEntry]:
    """Build download list while preserving manifest status and failing closed."""
    entries = []
    for item_data in _load_download_manifest():
        # `_load_download_manifest` returns validated dumps for compatibility with
        # existing internal callers. Re-validation keeps this boundary defensive.
        try:
            item = DownloadManifestEntry.model_validate(item_data)
        except ValidationError:
            continue
        filename = item.filename

        file_path = _safe_local_file(filename)
        size_bytes = None
        size_display = None
        if file_path is not None:
            try:
                size_bytes = file_path.stat().st_size
                size_display = _format_size(size_bytes)
            except OSError:
                file_path = None
                size_bytes = None
                size_display = None

        if item.status == "available":
            integrity_ok = file_path is not None
            if integrity_ok and item.checksum_sha256:
                integrity_ok = _sha256_matches(file_path, item.checksum_sha256)
                if not integrity_ok:
                    logger.warning("Download checksum mismatch filename=%s", filename)
            status: DownloadStatus = "available" if integrity_ok else "coming_soon"
            url = item.url if integrity_ok else "#"
            if not integrity_ok:
                size_bytes = None
                size_display = None
        elif item.status == "beta":
            status = "beta"
            url = item.url
        else:
            status = "coming_soon"
            url = "#"
            size_bytes = None
            size_display = None

        entries.append(DownloadEntry(
            platform=item.platform,
            architecture=item.architecture,
            filename=filename,
            url=url,
            version=APP_VERSION,
            size_bytes=size_bytes,
            size_display=size_display,
            status=status,
            notes=item.notes,
            checksum_sha256=item.checksum_sha256,
            evidence_url=item.evidence_url,
            evidence_label=item.evidence_label,
        ))

    return entries


def _download_list_response(user_agent: str) -> DownloadListResponse:
    detected = detect_platform(user_agent)
    return DownloadListResponse(
        version=APP_VERSION,
        detected_platform=detected["platform"],
        downloads=_build_download_entries(),
    )


def _download_file_response(filename: str) -> FileResponse:
    """Build a response only for a manifest-authorized verified artifact."""
    safe_name = Path(filename).name
    if (
        not filename
        or safe_name != filename
        or filename in {".", ".."}
        or "/" in filename
        or "\\" in filename
        or "\x00" in filename
    ):
        raise HTTPException(status_code=400, detail="Invalid filename")

    entry = next(
        (
            candidate
            for candidate in _build_download_entries()
            if candidate.filename == safe_name and candidate.status == "available"
        ),
        None,
    )
    file_path = _safe_local_file(safe_name)
    if entry is None or file_path is None:
        raise HTTPException(
            status_code=404,
            detail=f"Download '{safe_name}' is not available.",
        )

    return FileResponse(
        path=str(file_path),
        filename=safe_name,
        media_type="application/octet-stream",
        headers={"Content-Disposition": f'attachment; filename="{safe_name}"'},
    )


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.get("", response_model=DownloadListResponse)
@router.get("/list", response_model=DownloadListResponse)
async def list_downloads(request: Request):
    """Return all available downloads with platform auto-detection."""
    return _download_list_response(request.headers.get("user-agent", ""))


@router.get("/detect", response_model=PlatformDetectResponse)
async def detect_user_platform(request: Request):
    """Auto-detect the user platform and recommend the best download."""
    user_agent = request.headers.get("user-agent", "")
    detected = detect_platform(user_agent)

    recommended = None
    entries = [
        entry for entry in _build_download_entries()
        if entry.platform == detected["platform"]
        and entry.status == "available"
        and entry.url
        and entry.url != "#"
    ]
    exact = next((entry for entry in entries if entry.architecture == detected["architecture"]), None)
    universal = next((entry for entry in entries if entry.architecture == "universal"), None)
    selected = exact or universal or (entries[0] if entries else None)
    if selected:
        recommended = selected.url

    return PlatformDetectResponse(
        platform=detected["platform"],
        architecture=detected["architecture"],
        recommended_download=recommended,
    )


@router.get("/file/{filename:path}")
async def serve_download(filename: str):
    """
    Serve a manifest-authorized, runtime-verified download file.
    """
    return _download_file_response(filename)


@public_router.get("/downloads/manifest.json", response_model=DownloadListResponse, include_in_schema=False)
async def public_download_manifest(request: Request):
    """Expose runtime-verified public download truth, never the raw manifest."""
    return _download_list_response(request.headers.get("user-agent", ""))


@public_router.get("/downloads/{filename:path}", include_in_schema=False)
async def serve_public_download(filename: str):
    """Backward-compatible guarded public artifact route."""
    return _download_file_response(filename)

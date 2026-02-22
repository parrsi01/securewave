# Multi-Protocol Phase 4 Release Report

Date (UTC): 2026-02-21
Branch: `release/multiprotocol-live-only`

## Scope Completed

1. Added a manifest-driven release pipeline:
   - `scripts/build_release_all.sh`
   - Generates:
     - `artifacts/releases/<version>/version.json`
     - `artifacts/releases/<version>/checksums.txt`
   - Publishes latest files to `static/downloads/`
   - Removes stale top-level downloads from website serving path

2. Replaced hardcoded download metadata in backend:
   - `routes/downloads.py` now reads `static/downloads/version.json`
   - Added `GET /api/downloads/manifest`
   - `GET /api/downloads` and `GET /api/downloads/detect` now resolve real file presence before reporting availability

3. Rewired website download behavior to API/manifest:
   - `static/js/downloads.js`
   - `static/js/os_download.js`
   - Removed hardcoded filename assumptions from client JS

4. Added release safety checks and tests:
   - `scripts/ci_multiprotocol_safety_check.sh` now validates release manifest + no key material in downloads
   - `tests/unit/test_download_manifest.py` validates manifest availability and recommendation logic

5. Added operator documentation:
   - `docs/release_process.md`

## Stale Download Cleanup Behavior

`build_release_all.sh` now clears stale top-level files in `static/downloads/` and repopulates from the current release manifest/artifact set.

## Platform Status in This Workflow

- Linux: primary artifact is `.deb` (built automatically)
- Windows: ingested from native Windows artifact drop when provided
- macOS: ingested from native macOS DMG when provided; otherwise preview/unavailable in manifest
- Android: optional APK/AAB ingest/build
- iOS: TestFlight/App Store only (no direct website binary)

## Risks / Follow-Ups

- Production Windows/macOS publishing still depends on native signed artifacts from their native build/signing hosts.
- `.deb` is checksum-verified but not package-signed; add repository signing in a future hardening phase if required.
- Website depends on manifest freshness; release process must run before each public version change.

## Verification Refresh (2026-02-22)

This branch already contained the Phase 4 release pipeline and website manifest integration. This run revalidated the build script and website wiring with the current version (`4.0.0+1`).

Commands executed:
- `./scripts/build_release_all.sh`
- `./scripts/verify_website.sh`

Results:
- Release build script passed and rebuilt/published:
  - `artifacts/releases/4.0.0+1/version.json`
  - `artifacts/releases/4.0.0+1/checksums.txt`
  - `static/downloads/version.json`
  - `static/downloads/checksums-4.0.0-1.txt`
  - `static/downloads/securewave-linux-arm64-4.0.0-1.deb`
- Linux package build succeeded (`securewave_app/build/packaging/securewave-vpn_4.0.0+1_arm64.deb`).
- Website verification passed with warnings only (`Errors: 0`, `Warnings: 725`), consistent with the existing broad static-link checks.

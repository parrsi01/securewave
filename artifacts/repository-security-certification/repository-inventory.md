# Repository inventory summary

Audit base: `origin/master` at `d8ddec2d`

- 1,510 tracked files before this certification change set.
- Primary first-party surfaces: Python/FastAPI, Dart/Flutter, shell, Docker,
  Terraform, JavaScript/static site, native Linux/Windows/macOS/Android code,
  migrations, and GitHub Actions.
- Four workflow files existed on master: CI, Linux release, manual Linux x64
  Debian evidence, and Apple release validation.
- Backend tests live under `tests/`; Flutter tests under `securewave_app/test/`;
  simulated VPN/network tests under `securewave-tests/`.
- 91 tracked artifact files existed, including 16 legacy raw-output extensions.
  No private-key, authorization-header, cookie-header, or credential-URL match
  was found in the artifact scan. Matched values were never printed.
- Four downloadable package/archive files were tracked under
  `static/downloads/`; no availability status was changed.
- README referenced a nonexistent `tests_real/` path and an unreported remote
  `flutter` branch model; both descriptions were corrected.
- SECURITY and CODEOWNERS coverage was absent and has been added.
- Docker build context had no `.dockerignore`; a deny-by-default context is now
  enforced.

Legacy raw evidence is not automatically deleted. The repository guard freezes
the current baseline and rejects additions while owners decide retention and
redacted-summary replacements.

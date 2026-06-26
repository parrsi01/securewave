# SecureWave DevOps And Risk Summary

Last updated: 2026-06-26.

This note summarizes the bugs, vulnerabilities, and DevOps gaps observed from
the local repository checks in this pass. It is not live tunnel proof and does
not widen the Linux v1 release scope.

## Fixed In This Pass

- CI branch coverage: `.github/workflows/ci-cd.yml` did not run on the active
  `flutter` branch. The workflow now runs on `main`, `master`, `develop`, and
  `flutter`.
- Dependency advisories: `pip-audit -r requirements.txt` reported 26 known
  vulnerabilities across `python-multipart`, `cryptography`, `pillow`,
  `python-dotenv`, transitive `pyasn1`, and transitive `starlette`. Direct pins
  were upgraded and `pyasn1` was pinned to a fixed release.
- Container runtime packaging: `Dockerfile` started `main.py` without copying
  required runtime packages such as `routes/`, `utils/`, `config/`, `ml/`,
  `infrastructure/`, and `background_tasks.py`. The image now copies the
  runtime modules explicitly and runs as a non-root `securewave` user.
- Static security scan coverage: CI now runs `pip-audit` and Bandit with
  medium/high thresholds.
- Website DevOps coverage: CI now runs `scripts/verify_website.sh` and
  `scripts/verify_ui_v1.sh`.
- Mobile DevOps coverage: CI now includes an Android debug build gate for the
  Flutter app. Linux desktop analyze/test/release build remains in place.
- Apple DevOps coverage: `.github/workflows/apple-release.yml` now validates
  iOS on a macOS runner with CocoaPods, workspace guardrails, store metadata
  checks, and an unsigned release build.
- Production image delivery: `.github/workflows/container-release.yml` now
  builds and publishes backend images to GHCR for tags and manual runs.
- Production deployment guardrail: `scripts/deploy_production.sh` now provides
  an explicit, confirmation-gated deploy path for a prepared Hetzner host.
- Smoke-script URL safety: `scripts/live_flutter_runtime_smoke.py` now rejects
  non-HTTP(S) schemes before calling `urllib.request.urlopen`.
- Repository hygiene: `.gitignore` and `.dockerignore` now exclude generated
  Flutter, static-site, preview, local private, and runtime state directories.
- Bandit low-noise cleanup: app-route low findings were reduced by replacing a
  swallowed telemetry optimizer exception with debug logging and replacing a
  production `assert` with an explicit HTTP 503.
- Flutter dependency modernization: compatible direct Flutter package
  constraints and lockfile entries were updated for `dio`, `path_provider`,
  `uuid`, `flutter_riverpod`, `connectivity_plus`, `flutter_dotenv`,
  `flutter_secure_storage`, and `flutter_launcher_icons`.

## Current Local Validation

Run the local gate with:

```bash
bash scripts/devops_preflight.sh
```

For a backend/static-only pass:

```bash
SKIP_FLUTTER=true bash scripts/devops_preflight.sh
```

The preflight runs repository guards, website static QA, dependency audit,
Bandit, backend smoke/security tests, and Flutter analyze/tests unless skipped.

Validation completed in this pass:

- `bash scripts/devops_preflight.sh` passed.
- `.venv/bin/python -m pytest tests/unit tests/integration tests/smoke tests/security -q`
  passed with 299 tests.
- Full high-confidence Bandit low/medium/high scan reported no issues.
- `docker build -t securewave:devops-smoke .` passed.
- Container import smoke passed and confirmed generated static/runtime folders
  are not present in `/app/static`.

## Remaining Risks And TODO

- Live VPN tunnel proof is still separate from CI. CI can validate code paths
  and package builds, but it does not prove a real WireGuard/OpenVPN tunnel,
  interface, route, or traffic flow.
- Local Android packaging is blocked on this ARM64 Linux host because Google's
  Android SDK platform-tools/build-tools binaries installed by `sdkmanager` are
  x86-64 ELF binaries. The GitHub Actions Android gate remains the authoritative
  APK proof unless an ARM64-compatible Android SDK or x86-64 runner is used.
- iOS unsigned build validation is automated on macOS. App Store/TestFlight
  signing still requires Apple signing secrets and a follow-up `flutter build
  ipa`/upload lane.
- Production image publishing is automated. A live production deploy still
  requires a prepared Hetzner host, SSH route, production `docker-compose.yml`,
  environment secrets, and an explicit deploy invocation.
- The worktree cleanup now ignores generated artifact roots, duplicate local
  app scratch, and runtime usage state. Use `bash scripts/worktree_cleanup_status.sh`
  to see any remaining visible local files before staging.
- Bandit still has intentional low-severity operator-script subprocess findings
  at medium confidence when run without confidence thresholds. CI blocks
  medium/high findings, and high-confidence low findings are currently clean.
- Flutter major-version migrations remain for Riverpod 3, secure storage 10,
  connectivity_plus 7, flutter_dotenv 6, intl 0.20, platform_info 5, and
  flutter_lints 6.

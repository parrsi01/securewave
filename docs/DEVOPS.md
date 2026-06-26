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
- Smoke-script URL safety: `scripts/live_flutter_runtime_smoke.py` now rejects
  non-HTTP(S) schemes before calling `urllib.request.urlopen`.
- Repository hygiene: `.gitignore` and `.dockerignore` now exclude generated
  Flutter, static-site, preview, local private, and runtime state directories.

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
  passed with 298 tests.
- `docker build -t securewave:devops-smoke .` passed.
- Container import smoke passed and confirmed generated static/runtime folders
  are not present in `/app/static`.

## Remaining Risks And TODO

- Live VPN tunnel proof is still separate from CI. CI can validate code paths
  and package builds, but it does not prove a real WireGuard/OpenVPN tunnel,
  interface, route, or traffic flow.
- Local Android packaging could not be run on this machine because no Android
  SDK is installed. The GitHub Actions workflow now provisions an Android SDK
  and runs `flutter build apk --debug`.
- iOS build and signing are not automated in this Ubuntu CI workflow. The repo
  keeps workspace guardrails, but App Store/TestFlight signing still requires
  macOS runner setup and secrets.
- Production deploy is not automated from this workflow. Docker build is gated,
  but pushing an image and rolling the Hetzner host should remain a separate,
  explicit deployment step.
- The worktree still contains many pre-existing untracked reports and generated
  directories. They were not staged in this pass because they include broad
  artifacts and private/local material.
- Bandit still reports low-severity noise in demo/test scripts when run without
  thresholds. CI blocks medium/high findings; low findings should be triaged
  separately before being used as a release blocker.

# Redacted Baseline Results

Baseline date: 2026-07-09 UTC. Scope: local source and test fixtures only.

| Check | Command or source | Outcome | Interpretation |
| --- | --- | --- | --- |
| Python compile | `python3 -B -m compileall -q` over tracked `*.py` | Passed | Source syntax only. |
| Backend test suite | `SKIP_INSTALL=true bash scripts/run_backend_tests.sh` | Passed: 288 tests | Test mode uses SQLite, mock WireGuard, and mocked/demo behavior. |
| Flutter analysis | `cd securewave_app && flutter analyze` | Passed | No analyzer issues. |
| Flutter tests | `cd securewave_app && flutter test` | Passed: 24 tests | Unit/widget coverage only. |
| Flutter Linux build | `cd securewave_app && flutter build linux --debug` | Passed | Compiles runner/helper daemon; does not prove install, helper IPC, or a tunnel. |
| Website checks | `bash scripts/verify_website.sh` and `bash scripts/verify_ui_v1.sh` | Passed | Static file/link/theme checks only. |
| Shell syntax | `bash -n` over all tracked shell files | Passed | Does not execute scripts. |
| JavaScript syntax | `node --check` over tracked `static/js/*.js` | Passed | No browser/runtime coverage. |
| Manifest syntax | Node JSON parse of `static/downloads/manifest.json` | Passed | Does not attest the referenced binaries. |
| Release/workspace guards | `bash scripts/verify_release_guards.sh`; `bash scripts/check_xcworkspace_usage.sh` | Passed | Source-string guards only. |
| Compose config | Dummy-value `docker compose ... config --quiet` | Passed | Interpolation/syntax only; no containers started. |
| Clean Docker builds | `Dockerfile` and `Dockerfile.simple` from a clean staged archive | Passed | Uses a ~51 MB clean context; no dirty-worktree/private files were sent. Non-test app import remains blocked. |
| Linux package contracts | `tests/unit/test_linux_runtime_guards.py` and `test_linux_vpn_runner_contract.py` | Passed: 10 tests | Text/package contract checks, not runtime proof. |

## Verified blockers

- A non-test import of `main` fails at the SlowAPI-decorated VPN profile route
  because the handler lacks a `Request` argument. Tests hide this by enabling
  `TESTING=true`.
- Fresh Alembic upgrades fail in two ways: default development auto-creates
  metadata before revision 0001, while auto-create-disabled upgrades reach
  revision 0005 and fail because `audit_logs` is absent.
- Before this baseline's Docker copy fix, the Docker source layout could not
  import `main` because `utils/` and other runtime imports were omitted. ARM64
  builds also needed temporary `gcc`/`libc6-dev` to compile the pinned `psutil`.
  Both Dockerfiles now build from a clean staged archive, but a non-test import
  still fails at the SlowAPI VPN route and a runnable container remains
  unproven until that and the migration defects are repaired.
- The local AppImage build is blocked because `appimage-builder` is absent.
- No tracked Python lint configuration/tool exists. `shellcheck`, `gitleaks`,
  actionlint, and yamllint are unavailable locally; no `.gitleaks.toml` is
  tracked. The staged-file secret hook is used for this baseline change set.

## Explicitly not run

- Production deployment, public-download publication, release signing,
  certificate procurement, SMTP/email-provider work, live VPN connection,
  root-required package installation, external load tests, or external cloud
  operations.

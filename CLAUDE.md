# SecureWave VPN — Project Memory

## AGENT DELEGATION (READ FIRST)

**ALWAYS use the `securewave-vpn-architect` agent for every task in this project.**
This applies to ALL work: code changes, audits, tests, deployments, debugging,
infrastructure, security, and research. Do not handle SecureWave tasks in the
main conversation without delegating to this agent first.

---

## Project Overview

SecureWave is a multi-platform VPN SaaS app targeting paying users. It is in
active development on the `release/multiprotocol-live-only` branch.

- **App**: Flutter 3.32+ (iOS, Android, macOS, Windows, Linux)
- **Backend**: Python 3.11 / FastAPI / PostgreSQL
- **VPN**: WireGuard · OpenVPN · IKEv2/IPsec (multiprotocol)
- **Payments**: Stripe subscriptions + webhooks
- **Infra**: Hetzner Cloud · Ubuntu · Nginx · systemd
- **CI/CD**: GitHub Actions (`ci-cd.yml`, `flutter-release.yml`)

---

## Tech Stack Details

- State management: Riverpod (StateNotifier pattern)
- Navigation: GoRouter
- Design system: Material 3, Teal #1B6B68, Manrope font, "Calm Slate"
- Design tokens: `securewave_app/lib/ui/app_ui_v1.dart` (AppUIv1 class)
- HTTP client: Dio with JWT Bearer interceptor
- Storage: flutter_secure_storage for tokens, wg keys
- Logging: AppLogger (structured JSON output)

---

## Key Commands

```bash
# Flutter
/home/sp/flutter/bin/flutter pub get
/home/sp/flutter/bin/flutter analyze --no-fatal-infos
/home/sp/flutter/bin/flutter test
/home/sp/flutter/bin/flutter build linux

# Backend (always use .venv)
.venv/bin/python -m pytest tests/ -x -q --tb=short
TESTING=true DEMO_MODE=true WG_MOCK_MODE=true python3 -m pytest tests/ -v
uvicorn main:app --reload --port 8080

# Git
git status && git log --oneline -5
git add <specific files> && git commit -m "type: description"
```

---

## Key File Map

```
securewave_app/lib/
  core/config/app_config.dart           # URL resolution, env loading
  core/constants/app_constants.dart     # HTTPS fallback URLs, app version
  core/services/vpn_service.dart        # ChannelVpnService, capabilities
  core/services/protocol_selector.dart  # protocol resolution (no auto allowed)
  core/state/vpn_state.dart             # VpnStateNotifier, state machine
  core/state/app_state.dart             # global app state
  core/models/vpn_protocol.dart         # VpnProtocol enum + storage helpers
  core/logging/app_logger.dart          # structured logging
  features/auth/auth_controller.dart    # login/register/session flow
  services/api_client.dart              # Dio client (logs baseUrl on init)
  linux/runner/my_application.cc        # C++ GTK native VPN bridge
routes/vpn.py                           # FastAPI VPN endpoints (multiprotocol)
routes/auth.py                          # FastAPI auth + JWT
main.py                                 # FastAPI app entry
infrastructure/hetzner/                 # Hetzner provisioning scripts
scripts/                                # release_preflight.sh, pre-commit-hook.sh
artifacts/                              # audit reports (write all reports here)
```

---

## Enforced Invariants (must never regress)

1. `VpnProtocol.auto` must be resolved BEFORE reaching `VpnService.connect()`
2. All fallback URLs use HTTPS (`https://138.199.204.139/...`)
3. Release builds using hardcoded fallback log `INSECURE_FALLBACK` via AppLogger.error
4. `api_client.dart` logs `apiBaseUrl` at construction
5. WireGuard capability on Linux gated on `wg_installed && can_elevate`
6. `my_application.cc` connect handler rejects NULL and `"auto"` with `protocol_unresolved`
7. All 4 privilege automation catch blocks log `error + stackTrace` (no silent `catch (_)`)
8. `desiredOn = false` on ALL failure/timeout paths in state machine
9. Connect guard: 45s outer timeout + 30s runtime timeout + 64 reconcile iteration cap
10. Auto-reconnect: 10s minimum cooldown between attempts

---

## Known Open Issues

| Issue | Location | Severity |
|-------|----------|----------|
| `g_spawn_check_exit_status` deprecated | my_application.cc | MEDIUM |
| `fl_method_channel_set_method_call_handler` API changed | my_application.cc | MEDIUM |
| RadioListTile deprecation (groupValue/onChanged) | settings_screen.dart + others | LOW |
| macOS VPN not implemented | AppDelegate.swift | HIGH |
| macOS Release.entitlements missing VPN capability | entitlements file | HIGH |

---

## Security Rules

- NEVER commit `.env`, secrets, or API keys
- NEVER log WireGuard private keys or JWT tokens
- Pre-commit hook: `scripts/pre-commit-hook.sh` (secret detection) — must pass
- Release preflight: `scripts/release_preflight.sh` — must pass before tagging
- Hetzner token must not appear in any committed file
- All endpoint inputs validated via Pydantic + `utils/input_sanitizer.py`

---

## Audit Reports

All reports go to `artifacts/` with naming: `sonnet_<topic>_report.md`

Recent audits:
- `artifacts/sonnet_debug_audit_report.md` — full codebase audit (2026-02-24)
- `artifacts/sonnet_env_catalog_fix_report.md` — env/URL/catalog fixes
- `artifacts/sonnet_protocol_resolution_report.md` — protocol resolution fixes
- `artifacts/sonnet_linux_execution_report.md` — Linux execution path
- `artifacts/sonnet_state_machine_stability_report.md` — state machine verification

---

## Git Workflow

- Main branch: `main`
- Active branch: `release/multiprotocol-live-only`
- Commit format: `type: description` where type = feat/fix/refactor/test/docs/chore
- Always add specific files (not `git add .`)
- Never commit `.env`, `*.local.json` containing secrets, or binary artifacts

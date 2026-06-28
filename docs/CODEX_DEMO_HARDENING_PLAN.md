# Codex Implementation Plan — Demo Hardening + Real-Gap Closure

**Author context:** Generated from a full read of the repo on 2026-06-28.
**Owner of execution:** Codex (VS Code extension / CLI / App).
**Demo target (fixed):** Flutter **Linux desktop** app (`flutter run -d linux`) →
**live API** `https://api.securewaveapp.com/api` (verified UP at plan time).
**Goal:** Finish genuinely-incomplete pieces **and** drive demo runtime-error
probability **< 10%** for the login → servers → connect → usage → disconnect flow.

> Branch rule: work on `flutter` for app/UI, `master` for backend/docs/packaging.
> Pull latest before starting; commit + push after each user-approved change.
> `flutter analyze` must stay at 0 issues; `flutter test` and `pytest` must stay green.

---

## 0. Verified-good baseline (do NOT redo)

| Area | State | Evidence |
|------|-------|----------|
| `flutter analyze` | 0 issues | ran clean |
| `flutter test` | 33 pass | ran clean |
| Live API | `/api/health` ok, `/api/downloads` ok | curl |
| Native bridge | WG/OpenVPN/IKEv2 handlers complete; 30s WG timeout; cleanup paths exist | `linux/runner/my_application.cc` |
| Helper | installed, contract v6 == required v6 | `/usr/local/libexec/securewave-wg-quick.contract` |
| Tooling | `wg-quick`, `wg`, `pkexec`, `openvpn`, `ipsec`, `resolvectl` present | PATH check |
| Honesty invariant | app never fakes "connected"; mock is opt-in & banner-labeled | `vpn_service.dart`, `app.dart` |
| Boot | 10s timeout + safe-mode fallback | `boot_controller.dart` |

**Implication:** the app code is solid. The demo risk is **operational/runtime**,
concentrated in the *real WireGuard tunnel* path and *live-account* state. Most
of this plan is robustness + a safe presentation path, not app rewrites.

---

## 1. Risk → mitigation map (the < 10% lever)

| # | Risk | Sev | Root cause | Mitigation (task) |
|---|------|-----|-----------|-------------------|
| R1 | `pkexec` password prompt on every connect/disconnect; cancel or missing PolicyKit agent → `vpn_permission_required` | **HIGH** | `spawn_wg_quick_async` escalates via pkexec | T1 (presentation mode) + T5 (polkit rule for real-tunnel path) |
| R2 | Real tunnel reroutes **all** traffic through Hetzner; the live API calls + screen-share/SSH now depend on tunnel egress/DNS | **HIGH** | `AllowedIPs = 0.0.0.0/0` | T1 (no reroute in presentation mode) + T6 (demo on local console; verify egress) |
| R3 | Repeated runs register devices → free-plan "device limit reached" | MED | each connect registers a peer | T2 (device reset/preflight) |
| R4 | No prebuilt Linux bundle; first `flutter run` cold-compiles, may fail | MED | `build/linux` empty | T3 (prebuild step in preflight) |
| R5 | Live inventory returns 0 servers / 5xx → empty catalog or profile failure | MED | backend state | T2 (preflight asserts inventory) |
| R6 | Email verification / password reset (SMTP) unfinished | LOW (demo) / real gap | TODO.md | T7 (finish SMTP) |
| R7 | Leftover `wg0` / `wg-quick@wg0.service` from host baseline conflicts with a fresh connect | MED | host had pre-existing wg0 (Section 4 note) | T2 (preflight detects + offers cleanup) |
| R8 | First-connect latency (pkexec + handshake) approaches 30s timeout on a slow box | LOW | `kWgQuickTimeoutMs` | T4 (rehearse; optional bump + warm-up) |

**Single highest-leverage decision:** for a *live audience*, default to
**Presentation Mode (T1)** — real backend, simulated tunnel, no pkexec, no
system reroute, clearly labeled. Keep the real-tunnel path (T5/T6) as the
"prove it's real" segment done once, deliberately, on the local console.

---

## 2. Tasks

### T1 — Presentation Mode: live API + simulated tunnel  ⭐ (highest priority)
**Why:** removes R1 + R2 (the two HIGH risks) without dishonesty.
**Files:** `securewave_app/lib/core/config/app_config.dart`,
`securewave_app/lib/core/state/app_state.dart`,
`securewave_app/lib/ui/app_ui_v1.dart` (Connect screen + status descriptor).

Implement a new, independent flag — **do not reuse `useMockApi`**:
- Add `bool simulateTunnel` to `AppConfig`, sourced from env
  `SECUREWAVE_SIMULATE_TUNNEL` / `--dart-define=SECUREWAVE_SIMULATE_TUNNEL=true`
  (default `false`; forced `false` in release builds like `useMockApi`).
- In `vpnServiceProvider`: when `simulateTunnel` is true and `useMockApi` is
  false, return `ChannelVpnService(fallback: MockVpnService(), allowFallback:
  true)` **but** force the simulated path (do not even probe native) — simplest:
  return `MockVpnService()` directly so connect/disconnect/trafficStats never
  touch pkexec or the channel.
- **Honesty (mandatory):** when `simulateTunnel` is on, the Connect screen MUST
  show a persistent banner `Simulated tunnel — presentation mode. Not a real
  VPN.` and the status label MUST read `Simulated (not encrypted)` instead of
  `VPN connected`. Reuse the existing `useMockApi` banner pattern at
  `app_ui_v1.dart:541`. This preserves the repo invariant ("never mark connected
  unless native reports success") because the state is explicitly labeled.
- Live API still serves auth/servers/account/plan/usage, so the demo shows real
  login, real server catalog, real account — only the tunnel is simulated.
- `MockVpnService` returns `countersAvailable=false`, so **no fake usage is
  reported to the live backend** — keep that property (do not synthesize usage).

**Acceptance:**
- `SECUREWAVE_SIMULATE_TUNNEL=true flutter run -d linux` → login against live
  API works, servers load live, Connect shows "Connecting → Simulated" with no
  pkexec prompt, Disconnect returns to disconnected, no `wg0` ever created
  (`ip link show type wireguard` stays empty).
- With the flag unset, behavior is byte-identical to today (real tunnel path).
- `flutter analyze` 0 issues; add a unit test mirroring
  `test/api_client_fallback_test.dart` asserting simulateTunnel keeps live API
  but simulated tunnel.

### T2 — Pre-flight + device/interface reset script
**Why:** removes R3, R5, R7; makes the live-account state deterministic.
**Files (new):** `scripts/demo_preflight.sh` (+ reuse `routes/devices.py` revoke
endpoint and `scripts/live_flutter_runtime_smoke.py`).

Script must, and print PASS/FAIL per check:
1. `curl -fsS https://api.securewaveapp.com/api/health` and `/api/downloads`.
2. Assert server inventory non-empty via the same `/vpn/servers?device_type=linux`
   the app calls; fail loudly if 0.
3. Log in with the **demo account** (env `DEMO_EMAIL`/`DEMO_PASSWORD`), call the
   devices list endpoint, print active device count vs limit, and **revoke stale
   devices** down to 0 (or a known baseline) so the demo run won't hit the cap.
4. Detect leftover WireGuard interfaces (`ip link show type wireguard`) and any
   `wg-quick@*.service`; if found, print the exact `wg-quick down` / `systemctl
   stop` command and require explicit `--cleanup` to run it (never auto-tear a
   host service without the flag).
5. Confirm helper + contract: `/usr/local/libexec/securewave-wg-quick` exists and
   `.contract` ≥ 6.
6. Exit non-zero if any blocking check fails.

**Acceptance:** running `bash scripts/demo_preflight.sh` on a clean machine exits
0 and prints a green checklist; on a polluted machine it names the exact fix.

### T3 — Deterministic build step
**Why:** removes R4.
**Action:** preflight (T2) runs `flutter build linux --release` (or warms
`flutter run`) so the binary is compiled before the audience is watching; assert
the bundle exists at `securewave_app/build/linux/*/release/bundle/securewave_app`.
Document the one-time `apt` deps (`ninja-build`, `libgtk-3-dev`, etc.) in the
runbook (T4) so a cold machine can't fail mid-demo.

### T4 — Demo runbook + rehearsal checklist
**Files (new):** `docs/DEMO_RUNBOOK.md` (supersede the WireGuard-app-centric
`DEMO.md` for the Linux-app demo; link them).
Contents: exact commands, which mode for which segment, the two env flags, the
device-reset step, "demo on the local console not SSH", recovery steps if a
screen freezes, and a 6-step rehearsal that must pass twice before the demo.

### T5 — (Real-tunnel path) PolicyKit rule to avoid the live password prompt
**Why:** mitigates R1 for the deliberate "prove it's real" segment.
**Files:** `securewave_app/packaging/` (polkit policy) + helper docs.
Ship a polkit `.rules`/`.policy` that allows the demo user to run
`securewave-wg-quick` via the helper with `auth_admin_keep` or `yes` **for the
demo user/session only**, documented as demo-only (not a default install
behavior). Acceptance: with the rule installed, a real connect on the local
console brings up `wg0` with no interactive prompt; without it, behavior is
unchanged. Keep this OUT of the default `.deb` postinst.

### T6 — Real-tunnel egress sanity
**Why:** mitigates R2 for the real segment.
**Action:** in the runbook, require running the real-tunnel segment on the local
console; after connect, verify the live API is still reachable *through* the
tunnel (`curl https://api.securewaveapp.com/api/health` while connected) and that
egress IP shifted to the Hetzner node. If the API is unreachable through the
tunnel, that is a backend/routing bug — file it; do not demo the real tunnel
until it passes. (Reuse `scripts/linux_vpn_runtime_verifier.py` /
`linux_app_vpn_tunnel_proof.py`.)

### T7 — Finish SMTP (email verification + password reset)  [real gap]
**Why:** the only feature TODO.md flags as unfinished; surfaces as "Email
unverified" on the Account tab and a dead password-reset path.
**Files:** `services/email_service.py`, `services/enhanced_email_service.py`,
`routes/auth.py` (verify/reset endpoints), `utils/env_validation.py`
(`email_config_issues`), `.env.template`.
**Action:** wire a real provider (SMTP creds via env), make
`/api/health/email` return `ok`, send verification + reset mail, and confirm the
register→verify and reset flows end-to-end against a test inbox. Gate behind env
so an unconfigured machine degrades gracefully (current behavior) rather than
erroring. **Demo note:** not required for the < 10% target (register returns a
token directly), so schedule AFTER T1–T4. If time-boxed, ship verification only.

---

## 3. Backend local-run note (only if a local backend is ever used)
The demo uses the **live** API, so the local Postgres default is irrelevant to
it. But if anyone runs the backend locally, `database/session.py` defaults to
`postgresql+psycopg2://...localhost:5432` which is refused on this box, and
secrets are ephemeral. For any local run, set
`DATABASE_URL=sqlite:////tmp/securewave.db` + `ACCESS_TOKEN_SECRET` /
`REFRESH_TOKEN_SECRET` / `DEMO_MODE=true` / `WG_MOCK_MODE=true`. Capture this in
`scripts/run_backend.sh` env example. (Out of the critical path for this demo.)

---

## 4. Execution order & definition of done
1. **T1** Presentation Mode (kills the two HIGH risks) — *do first*.
2. **T2 + T3** Pre-flight + build determinism.
3. **T4** Runbook + rehearse twice.
4. **T5 + T6** Real-tunnel segment hardening (only if the real tunnel will be shown).
5. **T7** SMTP (real gap; after demo path is safe).

**Done when:**
- Presentation-mode dry run completes login→servers→connect→usage→disconnect with
  **zero** error toasts and no pkexec prompt, twice in a row.
- `scripts/demo_preflight.sh` exits 0 on the demo machine.
- `flutter analyze` 0 issues, `flutter test` + `pytest` green.
- Runbook reviewed; real-tunnel segment (if used) verified on local console.
- T7 either landed or explicitly deferred with the demo unaffected.

## 5. Verification commands
```bash
# App quality gates
cd securewave_app && flutter analyze && flutter test

# Presentation mode (safe live demo)
cd securewave_app && SECUREWAVE_SIMULATE_TUNNEL=true flutter run -d linux

# Live API + inventory + device reset
bash scripts/demo_preflight.sh            # add --cleanup to tear leftover wg ifaces

# Real-tunnel proof (local console only)
python3 scripts/linux_vpn_runtime_verifier.py
ip link show type wireguard               # expect wg0 only during real segment
```

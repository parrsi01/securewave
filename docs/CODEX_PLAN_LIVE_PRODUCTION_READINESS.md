# Codex Plan — Live Production Readiness (the "demo" IS the live product)

**Decision (user, 2026-06-28):** the demo is the **live version**. Every feature
must genuinely work for real users on the real product — not be demo-staged.
**Presentation Mode (`SECUREWAVE_SIMULATE_TUNNEL=true`) is demoted to a labeled
emergency fallback only**; the headline path is the real WireGuard tunnel +
live API working end to end.

**Target:** Flutter Linux app (installed `.deb`) → live API
`https://api.securewaveapp.com/api`, real tunnel up, real usage, < 10% runtime
failure for login → servers → connect → usage → disconnect.

**Branch:** app on `flutter`; packaging/scripts/docs/backend on `master`
(codex decides the app-code home per the merge plan).

---

## P0 — Connect privilege model: install + verify the EXISTING polkit rule  ⭐
**This is the real fix for the "pkexec prompt every connect" risk — not a hack.**

Verified facts:
- The helper `/usr/local/libexec/securewave-wg-quick` is installed and
  contract-matched (v6).
- A production polkit rule already exists at
  `securewave_app/packaging/linux/50-securewave-wg.rules`. It returns
  `polkit.Result.YES` (prompt-free) for the helper when the subject is the
  templated `__SECUREWAVE_ALLOWED_USER__`, the `securewave` user, or any member
  of the `sudo` group.
- **That rule is NOT installed in `/etc/polkit-1/rules.d/` on this machine**, so
  connect currently triggers a password prompt.

Tasks:
1. **Confirm the `.deb` postinst installs the rule.** It must copy
   `50-securewave-wg.rules` to `/etc/polkit-1/rules.d/50-securewave-wg.rules`,
   substitute `__SECUREWAVE_ALLOWED_USER__` with the installing user (or leave
   the sudo-group grant), set mode `0644`, and `systemctl restart polkit` (or let
   polkit hot-reload). If the postinst does NOT do this today, that is the gap —
   add it to the package build (`scripts/build_apps.sh` / `build_release.sh`).
2. **On the live/demo machine, install + verify now:**
   `sudo install -m0644 .../50-securewave-wg.rules /etc/polkit-1/rules.d/` then
   confirm a real connect raises `sw-wg` with **no** prompt for a sudo-group
   user.
3. **Verify least privilege:** the rule only allows the specific helper path and
   `wg show`; confirm the helper's `require_safe_config_path` still constrains
   config paths to `~/.config/securewave/*.conf` etc. (it does — keep it).
4. **Headless/Wayland note:** document that a PolicyKit authority must be running;
   with the rule installed there is no agent prompt, so headless is fine.

**Acceptance:** on a clean `.deb` install, a sudo-group user connects and
disconnects the real tunnel with zero password prompts; `ip link show type
wireguard` shows `sw-wg` only while connected; teardown leaves no residue.

## P1 — Real egress + DNS correctness through the tunnel
The full reroute (`AllowedIPs=0.0.0.0/0`) is **expected** VPN behavior — the goal
is that it works, not that it's avoided.
1. While connected, assert working internet **through** the Hetzner node:
   `curl -fsS https://api.securewaveapp.com/api/health` succeeds, a general site
   loads, and DNS resolves (the profile sets DNS — confirm `resolvectl` reflects
   it and there is no leak).
2. Confirm egress IP shifts to the Hetzner node (`curl https://api.ipify.org`
   before vs after). Reuse `scripts/linux_vpn_runtime_verifier.py` /
   `linux_app_vpn_tunnel_proof.py`.
3. If the live API is unreachable through the tunnel, that is a backend/routing
   defect on the node (NAT/forwarding/egress) — fix the node, do not ship.
4. Verify the kill-switch story: the app already flags "tunnel down, kill switch
   may be blocking" on connectivity loss with PostUp/PostDown hooks — confirm the
   live profile's hooks match the intended behavior so a dropped tunnel fails
   safe, not silently open.

**Acceptance:** connected session has working, leak-free internet via Hetzner and
a correct kill-switch posture; documented egress-shift evidence.

## P2 — Server inventory is real (no synthetic regions)
Contributor rule: do not present synthetic region aliases pointing at one IP as
distinct public regions.
1. Confirm `/vpn/servers?device_type=linux` (what the app calls) returns the real,
   deduplicated inventory and never 0 during business hours.
2. Each listed region must back a real, connectable endpoint; auto-select must
   resolve to a node that issues a working profile.
3. Add an inventory assertion to `scripts/demo_preflight.sh` (already planned) so
   an empty/duplicated catalog blocks go-live.

**Acceptance:** the Servers tab shows only real, connectable regions; auto-select
yields a working profile.

## P3 — Auth + email verification actually work (real users)
Because real users sign up, the email flows matter now (not just cosmetics).
- Execute **`docs/CODEX_PLAN_SMTP_EMAIL.md`** (T7) and treat it as in-scope, not
  deferred: verification email on register, working password reset,
  `/api/health/email` → ok. The Account tab's "Email verified/unverified" must
  reflect reality.

**Acceptance:** register → receive + complete verification → Account shows
verified; password reset works end to end.

## P4 — Session lifecycle for real use
1. **Reconnect:** validate the connectivity-driven auto-reconnect path on a real
   tunnel (drop Wi-Fi, restore) — it should re-establish without a stuck state.
2. **Device limits:** real users hit the plan cap; confirm the device list +
   revoke endpoints (`routes/devices.py`) work from the product (not only
   preflight), and the app surfaces "device limit reached" with a clear action.
3. **Cleanup on crash/exit:** if the app dies mid-session, ensure no orphaned
   `wg0` / stale config in `~/.config/securewave/`. Confirm the helper's
   `down`/`policy-clear` paths run on disconnect and document a recovery command.

**Acceptance:** reconnect recovers cleanly; device cap is enforced + actionable;
no orphaned interfaces after abnormal exit.

## P5 — Billing/subscription reality (if plans are user-visible)
`main.py` logs "STRIPE_SECRET_KEY not configured" locally. For the live product,
confirm the live backend has Stripe/PayPal configured and that plan/usage shown
in the app matches the real subscription. If billing is out of demo scope, gate
upgrade CTAs so they don't dead-end. Decide explicitly; don't show a half-wired
paywall.

**Acceptance:** plan/usage in-app matches backend truth; no broken purchase path.

## P6 — Observability + go/no-go gate
1. Extend `scripts/demo_preflight.sh` to assert P0 (polkit rule installed →
   prompt-free connect), P1 (egress works), P2 (inventory non-empty), and email
   health, producing a single PASS/FAIL go/no-go.
2. Ensure connect failures are diagnosable: the app's Diagnostics sheet + the
   structured backend logs (request_id, redacted) should let you triage a failed
   live connect in under a minute.

**Acceptance:** one command returns go/no-go; a deliberately broken connect is
traceable from app Diagnostics + backend logs.

---

## Presentation Mode's role now
Keep it shipped, but only as a **clearly-labeled fallback** if, at runtime, the
real tunnel is unavailable on a given machine (no polkit, missing tooling). It
must never be the silent default and must keep the "Not a real VPN" disclosure.
Do not let it mask a real P0/P1 failure — fix the real path first.

## Execution order
P0 (privilege) → P1 (egress) → P2 (inventory) → P3 (email) → P4 (lifecycle) →
P5 (billing) → P6 (gate). P0+P1 are the live-readiness blockers; everything else
is correctness/coverage. Touch no demo-only shortcuts; this is the product.

## Verification
```bash
# P0: rule installed + prompt-free connect (sudo-group user, local console)
ls /etc/polkit-1/rules.d/50-securewave-wg.rules
python3 scripts/linux_vpn_runtime_verifier.py --json --pkexec-timeout 60

# P1: egress through tunnel while connected
curl -fsS https://api.securewaveapp.com/api/health && curl -fsS https://api.ipify.org

# P2/P3/P6: consolidated gate
bash scripts/demo_preflight.sh --live-go-no-go
curl -fsS https://api.securewaveapp.com/api/health/email
```

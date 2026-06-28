# Codex Plan — Real-Tunnel Proof Segment (T5 + T6)

> **SUPERSEDED 2026-06-28 by `docs/CODEX_PLAN_LIVE_PRODUCTION_READINESS.md`.**
> The user confirmed the demo IS the live product, so the real tunnel is the
> headline, not an optional segment. The "demo-only polkit grant" framing in T5
> below is wrong: a **production** polkit rule already exists at
> `securewave_app/packaging/linux/50-securewave-wg.rules` (prompt-free for
> sudo-group / `securewave` user) — it just needs to be installed/verified (see
> P0 of the live-readiness plan). T6's egress verification is still valid and is
> folded into P1 there. Use the live-readiness plan as the source of truth; keep
> this doc only for the T6 verification detail.

**Status of parent work:** Presentation Mode + preflight + runbook landed in
commit `3481c3e93f4ae287cb60e234a5bd36589162f633` on `flutter`.
**This plan covers:** the OPTIONAL "prove it's a real VPN" segment shown once,
deliberately, on the local console — only relevant if the real WireGuard tunnel
will be demonstrated. If the demo is Presentation Mode only, skip this entirely.

**Why it's separate:** the real tunnel is the source of the two HIGH demo risks
(pkexec prompt + all-traffic reroute). This plan makes that one segment
deterministic instead of avoiding it.

---

## T5 — Remove the live pkexec password prompt (demo-only PolicyKit grant)

**Problem:** `spawn_wg_quick_async` (`securewave_app/linux/runner/my_application.cc`)
runs `pkexec --disable-internal-agent /usr/local/libexec/securewave-wg-quick up`,
so every connect/disconnect pops a password dialog and fails if the user cancels
or no PolicyKit agent is present.

**Deliverable:** a **demo-only** polkit grant, never shipped in the default `.deb`
postinst.
- Files (new): `securewave_app/packaging/polkit/securewave-demo.rules` (polkit
  ≥0.106 JS form) and a legacy `securewave-demo.pkla` fallback.
- Rule logic: allow `org.freedesktop.policykit.exec` **only** when the program is
  `/usr/local/libexec/securewave-wg-quick` **and** the requesting user is the
  demo user (parameterize the username), returning `polkit.Result.YES`
  (or `AUTH_ADMIN_KEEP` if a single auth is acceptable).
- Install/uninstall: document `sudo install -m 0644 securewave-demo.rules
  /etc/polkit-1/rules.d/49-securewave-demo.rules` and the matching `rm` for
  teardown. Make teardown part of the runbook so the grant does not linger.

**Acceptance:**
- With the rule installed, a real connect on the local console brings up `wg0`
  with **no** password dialog; disconnect tears it down silently.
- With the rule removed, behavior is identical to today (prompt returns).
- The default `.deb` install does NOT add this rule (grep postinst to confirm).

**Security note (call out in PR):** this is an intentional, scoped, demo-only
privilege relaxation. It MUST be removed after the demo. Document the exact blast
radius (any process able to act as the demo user could run the helper without
prompt).

---

## T6 — Real-tunnel egress + reroute sanity

**Problem:** `AllowedIPs = 0.0.0.0/0` reroutes all traffic through Hetzner. If the
node can't reach the public internet for the client, the live API the UI depends
on (usage report, account refresh) goes dark mid-demo; a screen-share/SSH session
can also drop.

**Deliverable:** a gating verification, reusing existing tooling.
- Run on the **local console only** (never over SSH) — state this in the runbook.
- Before the real segment, run `python3 scripts/linux_vpn_runtime_verifier.py
  --json --pkexec-timeout 60` and require PASS.
- While connected, assert: (a) `curl -fsS https://api.securewaveapp.com/api/health`
  still returns ok **through** the tunnel, and (b) egress IP equals the Hetzner
  node (compare `curl https://api.ipify.org` before/after). Reuse
  `scripts/linux_app_vpn_tunnel_proof.py` if it already captures egress shift.
- If the API is unreachable through the tunnel, that is a backend/routing defect:
  file it, and do NOT demo the real tunnel until it passes.
- After the segment: `wg-quick down` (or the app's disconnect), then confirm
  `ip link show type wireguard` is empty.

**Acceptance:** a scripted real-tunnel dry run on the demo box: connect (no
prompt, T5) → API reachable through tunnel → egress shifted → disconnect → no
`wg0` residue, completed twice.

---

## Execution
1. T5 polkit grant + install/teardown docs.
2. T6 verification wired into the runbook as a pre-segment gate.
3. Rehearse the real segment twice on the actual demo machine, local console.

**Do not** modify `AllowedIPs` or the escalation logic for the demo — that is a
product decision, out of scope here. This plan only makes the existing real path
predictable for one controlled segment.

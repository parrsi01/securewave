# SecureWave Linux Beta 1 acceptance report

Date: 2026-08-09

## Result

- **Demo application:** PASS. The actual Flutter UI completes registration,
  connect, deterministic usage, disconnect, reconnect, and logout without HTTP,
  native helper, OS keyring, or production infrastructure.
- **Portable ARM64 package:** PASS for Ubuntu 24.04 LTS ARM64 in an isolated
  systemd environment.
- **Public real-user beta:** BLOCKED. The deployed public API is an older,
  incompatible build: registration does not issue a token, valid login for a
  new account is email-verification gated, and `/api/vpn/target` is absent.
  Therefore no live profile, Hetzner peer, or public-egress proof was possible.

This distinction is intentional: a local kernel WireGuard proof is not a
Hetzner or Internet-egress proof.

## Accepted artifact

- file: `securewave-vpn_4.0.0+9_arm64.deb`
- SHA-256: `81a3f51f8c8621169e1f2514340e8cf9f86635f32c4e8d9556d97106a2a551dd`
- embedded source: `1a137a64f5b9aea1b2f663662f8cdcedefb82e36`
- embedded source state: `clean`
- architecture: `arm64`
- helper contract: `13`
- publication state: `false`

Two consecutive builds from the embedded source produced the same package
SHA-256.

## Evidence

| Gate | Result | Evidence |
| --- | --- | --- |
| Focused backend structure/API tests | PASS | 6 tests passed |
| Flutter analysis and focused tests | PASS | no analysis issues; 6 tests passed, including the complete demo widget journey |
| Demo network boundary | PASS | Flutter UI registration, profile, connect, deterministic health/usage, disconnect, reconnect, and logout used in-memory demo services and storage |
| PostgreSQL canonical auth | PASS | fresh PostgreSQL 16 migration; register, normalized email, duplicate rejection, invalid login, login, authenticated request, logout invalidation, relogin, and hashed-password storage passed |
| Clean package install | PASS | fresh Ubuntu 24.04 ARM64 container with systemd as PID 1 installed `4.0.0+9` without preinstalled GUI or VPN runtime packages |
| Runtime dependencies | PASS | GTK, libsecret, EGL, GLES, WireGuard, iproute2, iptables, and systemd dependencies resolved from package metadata |
| Helper installation | PASS | service enabled and active; socket present; packaged and installed helper/wrapper hashes matched; contract probe passed |
| GUI launch | PASS | packaged Flutter process remained alive for the 8-second headless X11 smoke window |
| Exact-artifact kernel WireGuard | PASS | `4.0.0+9` completed an authenticated kernel handshake, routed traffic, and reported 476 received / 596 transmitted bytes |
| Stability and cleanup | PASS | identical helper/wrapper bytes survived connected service restart, restored DNS/routes/firewall, removed a simulated stale runtime, and reconnected successfully |
| Package remove and purge | PASS | remove stopped and removed the helper/app while retaining Debian config state; purge removed the allowlist, config directory, and runtime group |
| Deployed public auth | BLOCKED | public registration returned 201 without a token; subsequent valid login returned 403 because the old deployment still requires email verification |
| Hetzner peer registration and public egress | BLOCKED | authentication stopped before profile issuance; no peer/config/private key was returned |
| Public download | BLOCKED | securewaveapp.com still serves `4.0.0+4`; the local `4.0.0+9` manifest remains `published: false` |

## Current public deployment audit

Read-only checks against the public domains found:

- `api.securewaveapp.com/api/health`: HTTP 200, service name
  `securewave-vpn-demo`
- `api.securewaveapp.com/api/ready`: HTTP 200, database connected
- `api.securewaveapp.com/version`: `4.0.0+4`, production, empty commit
- `securewaveapp.com/downloads/manifest.json`: public ARM64 package `4.0.0+4`
- `GET /api/vpn/target`: HTTP 404
- public registration requires `password_confirm`; it does not return an access
  token outside demo mode
- two generated acceptance registrations returned HTTP 201; no credentials were
  retained, both acceptance attempts stopped before profile issuance, and no
  WireGuard peer/config was obtained

The public website also still advertises billing, plans, device management, and
multiple desktop targets. Those claims do not match the simplified Beta 1
repository.

## Authentication regression cause

The failing public journey is contract divergence, not bad password hashing:

1. Commit `2a46582a` introduced the large email-verification, refresh-token,
   2FA, and account-gate stack. In production, registration returned a message
   instead of the bearer token expected by the Linux app.
2. Commit `de3a2eed` added the required `password_confirm` field.
3. Commit `4eb7feaf` (PR #26) reinforced the `email_verified` login gate, which
   is the observed HTTP 403 for a valid newly registered account.
4. Local candidate commit `420e92c3` replaced that stack with one email/password
   register/login/token path; it is not deployed publicly.

All listed commits record `SecureWave Team` as both author and committer. No
repository or PR metadata proves an AI model/tool attribution.

## Isolation and cleanup

The install/runtime proofs used disposable privileged ARM64 Ubuntu containers
with their own network namespaces and nested namespaces for WireGuard peers.
Canonical auth used a disposable PostgreSQL 16 container. The host-installed
SecureWave package was not changed. Test packages were removed and purged, and
all test containers and private temporary files were removed.

## Release decision

The repository is a working demo and an installable local beta candidate. It
must not be described as a completed public VPN beta until an authorized live
account obtains a profile from the deployed simplified backend, the client
registers a peer on the intended Hetzner server, public egress changes through
that tunnel, reconnect and restart succeed, cleanup is verified, and this exact
artifact is published.

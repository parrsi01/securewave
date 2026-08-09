# SecureWave Linux Beta 1 acceptance report

Date: 2026-08-09

## Final status

- **Real Beta:** PASS for Ubuntu 24.04 LTS ARM64.
- **Demo:** PASS; deterministic and offline.
- **Publication:** PASS for the exact ARM64 package and manifest.
- **Remaining internal blockers:** NONE.

The supported product path is intentionally small: one Linux ARM64 package,
one authenticated backend, PostgreSQL, one configured Hetzner WireGuard target,
and helper contract 13. amd64, alternate protocols, billing, email delivery,
and multi-server behavior remain out of scope.

## Accepted artifact

- file: `securewave-vpn_4.0.0+9_arm64.deb`
- SHA-256: `2dab0e2c57a9406b7b5d65758fe771ac4b2cd00816794c09372501ecad2f2275`
- embedded source: `90fe5a7607d91b40ecf2a381f4ae8bab1f6d23e7`
- embedded source state: `clean`
- architecture: `arm64`
- helper contract: `13`
- publication: `status=beta`, `published=true`

The package was built locally with the public HTTPS API URL, verified without
installation, installed in a fresh privileged Ubuntu 24.04 ARM64 systemd
container, and exercised through the live API.

## Real Beta evidence

| Gate | Result | Sanitized evidence |
| --- | --- | --- |
| Package build and integrity | PASS | `dpkg-deb` verification passed; exact SHA-256 above; source marker clean |
| Install and helper startup | PASS | package `4.0.0+9` installed; helper active; socket contract 13; beta user could access the helper |
| Registration | PASS | generated acceptance account returned HTTP 201; account was deleted after proof |
| Login and authenticated API | PASS | Flutter login succeeded; target/profile calls succeeded; restart process restored the stored session and `/auth/me` returned authenticated |
| Connect and handshake | PASS | three independent app processes connected to target `de-nue-1`; handshake present each time |
| Real traffic | PASS | RX/TX counters were non-zero in every cycle; representative final run: RX 4660/4660/4788 bytes and TX 2116/2116/2116 bytes |
| Public VPN egress | PASS | baseline `92.105.134.148`; connected egress `138.199.204.139` through the Hetzner target |
| Disconnect | PASS | clean disconnect in all three cycles; final helper verifier passed |
| Cold reconnect | PASS | second process connected, transferred traffic, and disconnected |
| App restart/session continuity | PASS | third process emitted `session_restored=true`, authenticated `/auth/me`, connected, transferred traffic, and disconnected |
| Logout and cleanup | PASS | logout HTTP 200; generated user rows 0; generated peer rows 0; host WireGuard peer count returned to baseline 86 |

The final sanitized live report is the three-cycle run labelled
`connect-disconnect`, `reconnect-cold-launch`, and `restart-session`.

## Demo evidence

The Flutter demo widget journey was run three times. Each run passed:

1. launch demo mode;
2. register and log in with deterministic in-memory storage;
3. connect, observe `Connected`, `Good`, and `12.0 KB transferred`;
4. disconnect and observe `Disconnected`;
5. reconnect with the same deterministic counters;
6. log out and return to `Welcome back`.

The demo API boundary test confirms no HTTP request is made, and the demo
service test confirms fixed RX/TX values and repeatable reconnect behavior.
Demo mode never invokes the native helper or production infrastructure.

## Blockers found and removed

### Legacy production schema rejected a valid peer

- **Root cause:** the live database retained a legacy `health_status NOT NULL`
  column without a default while the simplified peer insert omitted it.
- **Files/functions:** `models/wireguard_peer.py`,
  `services/vpn_peer_manager.py`, `routes/vpn.py`, and
  `database/session.py`.
- **Classification:** real internal blocker; fixed in backend commit
  `bf02b71e`.
- **Fix:** explicit `health_status="unknown"` plus a server default, sanitized
  `ValueError` handling, and SQLAlchemy parameter hiding. Existing PostgreSQL
  users and peers were preserved; the pre-deploy dump was verified.

### Helper socket became inaccessible after connect

- **Root cause:** `securewave-wg-quick up` recreated `/run/securewave` as
  `root:root`, defeating the `securewave` group permission on the socket.
- **Files:** `securewave_app/packaging/linux/securewave-wg-quick`,
  `securewave_app/packaging/linux/securewave-helper.service`, and
  `tests/test_beta_structure.py`.
- **Classification:** real internal runtime/package blocker; fixed in
  `f2eb5662`.
- **Fix:** preserve `root:securewave` in the `up` path and repair ownership in
  the service pre-start. The installed package was retested through all live
  cycles.

### Restart proof lacked an authenticated restore check

- **Root cause:** the existing smoke entrypoint always performed a fresh login,
  so it proved cold reconnect but not session restoration after process exit.
- **File:** `securewave_app/lib/runtime_vpn_probe.dart`.
- **Classification:** acceptance coverage gap; fixed in `90fe5a76`.
- **Fix:** a test-only restore-session mode reads secure storage, verifies the
  protected current-user endpoint, then uses the normal real WireGuard path.
  The normal application entrypoint and production mode are unchanged.

### Stale release metadata reported a false blocker

- **Root cause:** the report, manifest, and download page still described the
  old public API and checksum after the live backend and artifact were fixed.
- **Files:** this report, `static/downloads/manifest.json`,
  `static/download.html`, and `docs/LINUX_BETA.md`.
- **Classification:** documentation/public-artifact blocker; updated with the
  final evidence and exact checksum.

## Authentication blockers

The active path is one email/password flow:

`email/password -> PostgreSQL user row -> bcrypt verification -> bearer token ->
secure Linux storage -> Authorization header -> protected endpoint`.

Registration and login do not require WireGuard health, release certification,
email delivery/verification, payment state, protocol capability, or deployment
status. A `401` is reserved for an invalid or absent authenticated session;
profile/runtime failures are separate API errors. The live restart proof
confirmed that the stored bearer session survives process exit and protects
`/auth/me` on the next process.

## Configuration reduction

The Beta client requires one release setting: `SECUREWAVE_API_BASE_URL`, which
must be an HTTPS, non-local URL for a release package. Demo mode is an explicit
compile-time `SECUREWAVE_DEMO_MODE=true` boundary.

The production backend requires only its active data/control-plane settings:
`DATABASE_URL`, `ACCESS_TOKEN_SECRET`, `WG_ENCRYPTION_KEY`,
`WIREGUARD_SERVER_ID`, `WG_SSH_USER`, `WG_SSH_KEY_PATH`,
`WG_KNOWN_HOSTS_PATH`, and `ENVIRONMENT=production` (with `DB_SSL_MODE=require`
for the deployed PostgreSQL connection). Payment, SMTP, email verification,
registry, secondary-architecture, and alternate-protocol variables are not
startup requirements.

## WireGuard and Flutter blockers

The runtime now has one path from Flutter Connect to the backend profile,
server peer, contract-13 helper, `sw-wg`, policy routing, handshake, traffic,
DNS cleanup, and disconnect. Private-key handling, helper authorization,
configuration permissions, and route/firewall cleanup remain enforced.

The UI exposes login/register without obsolete protocol, region, payment,
email-verification, or capability gates. Connect is blocked only while the
user is unauthenticated, the operation is busy, or the real profile/runtime
operation fails; the UI reports the failure instead of switching to demo mode.

## Package and test blockers

The `.deb` builder requires only Flutter, Debian packaging tools, WireGuard
tools, and the package's declared runtime dependencies. It does not require a
registry login, deployment host, release approval variable, payment/email
provider, OpenVPN, strongSwan, or a second architecture.

No obsolete active tests were removed. The current suite was kept focused on
password hashing/token behavior, WireGuard lifecycle and cleanup, helper
privilege safety, package integrity, and demo/real separation; the helper
ownership regression assertion was added.

## External blockers

None remain for the supported Beta 1 path. amd64 and other distributions are
future scope, not blockers for the documented ARM64 Beta. No credentials were
manufactured or bypassed; generated acceptance accounts were deleted after
each run.

## Files changed

- `securewave_app/packaging/linux/securewave-helper.service`
- `securewave_app/packaging/linux/securewave-wg-quick`
- `securewave_app/lib/runtime_vpn_probe.dart`
- `tests/test_beta_structure.py`
- `static/downloads/manifest.json`
- `static/download.html`
- `docs/LINUX_BETA.md`
- `docs/BETA_ACCEPTANCE_REPORT.md`

No tracked files were deleted. The ignored package artifact is
`securewave_app/build/packaging/securewave-vpn_4.0.0+9_arm64.deb`.

## Final decision

ALL BETA/DEMO INTERNAL BLOCKERS REMOVED

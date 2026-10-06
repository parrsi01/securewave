# Current SecureWave state

Updated 2026-10-06. The published GitHub release baseline is **4.0.0+11**.
The installed **4.0.0+12 usage-recording candidate** is saved on
`codex/usage-recording-20261005`; its GitHub package release remains a draft.

## Current installed candidate

Installed package provenance identifies source
`c90dc03f5ccbab5fffb2fcaefedc72ea36e34527`, a clean tree, ARM64, and helper
contract 15. The VM rebooted on 2026-10-06 at 08:37:39 UTC. The post-reboot
helper, baseline network and cold-launch checks passed. The saved GUI session
expired; post-reboot VPN lifecycle and final usage persistence await sign-in.
See the [candidate verification](releases/4.0.0+12-verification.md) and
[post-reboot checkpoint](releases/4.0.0+12-post-reboot.md).

The UI preview is saved separately on `codex/flutter-ui-redesign`, source
`0e72924ea61924b34b969407fe05d5020dc4b4f7`. It is not integrated into the
usage-recording candidate. These branches preserve separate work for review.

## Historical 4.0.0+11 baseline and evidence (2026-10-04)

At that checkpoint, the ARM64 package was installed at
`/usr/lib/securewave/securewave_app` on the Ubuntu VM. Its installed AOT library
was checked against the rebuilt package.
The local helper is enabled, active, and exposes `/run/securewave/helper.sock`.
The user confirmed that the installed app is fully functional.

Automated verification: Flutter static analysis passed and all 17 Flutter
tests passed, including expired-session routing, duplicate registration,
endpoint-specific unauthorized responses, and existing WireGuard contracts.
A disposable-account live check using the actual Dart/Dio API service passed
readiness 200, fresh registration 201, login 200, and three authenticated
current-user requests 200. A deliberately wrong password returned 401 as
expected. Credentials were generated in memory and not logged or saved.

The core rollback tag `securewave-linux-core-verified` stays at
`7f6ec88e1fb995c4d1acf963308c0983ba9518b4`. It records the earlier independently
proved production WireGuard lifecycle. The new client release is identified
by its own GitHub release tag and package source metadata.

The user's functional confirmation is not an independently observed complete
reboot acceptance run. Actual reboot, post-reboot cold launch, VPN traffic,
and disconnect restoration remain unverified in this session.

## Languages, frameworks, and tools

| Layer | Current source or build tools |
| --- | --- |
| Linux application | Dart 3.11.1, Flutter 3.41.4 stable; application source in `securewave_app/lib` |
| HTTP and local storage | Dio 5.9.0 and Flutter Secure Storage 9.2.4, as resolved in `pubspec.lock` |
| Native integration | C++ native runner/helper, GTK 3, GLib/GIO, Flutter Linux embedding |
| Build | CMake (project minimum 3.13), Ninja, Flutter/Dart CLI, `dpkg-deb`, SHA-256 tooling |
| Backend source | Python 3.12 target, FastAPI, Pydantic, SQLAlchemy, psycopg2; pins in `requirements.txt` |
| Auth/security | PyJWT bearer tokens; bcrypt/passlib password hashes; desktop Secret Service/libsecret for local secrets |
| Database | Server-side PostgreSQL; the desktop app never connects to the database directly |
| VPN | WireGuard, `wg`, `wg-quick`, Linux IP routing, iptables, systemd-resolved |
| Operations | Bash scripts, systemd helpers, Gunicorn/Uvicorn, nginx, Hetzner infrastructure |
| Website | Existing production HTML/CSS/JavaScript frontend and manifest-guarded artifact routes |
| Source/release handoff | Git, GitHub CLI, versioned GitHub releases, SSH/SCP, Debian packages/APT |

Dependency pins describe this checkout and the recorded local build, not a
claim that every legacy production dependency has been redeployed or upgraded.
The source checkout is intentionally smaller than the existing website/API
deployment, which also retains legacy website/download routes.

GitHub currently reports open PyJWT security advisories, including a critical
advisory, against requirement manifests. This checkout pins PyJWT 2.13.0,
which is within reported vulnerable ranges. Dependency remediation and the
production exposure assessment are separate backend security work; functional
confirmation is not a security audit. Review the repository's
[Dependabot alerts](https://github.com/parrsi01/securewave/security/dependabot).

## Runtime boundaries

1. Flutter sends HTTPS requests to `https://api.securewaveapp.com/api`.
2. FastAPI authenticates the account and provisions a server peer from the
   client public key. PostgreSQL and server-management secrets remain server-side.
3. The unprivileged desktop app asks the restricted local helper to operate
   WireGuard through a Unix socket. The private key stays on the client.
4. Connection checks use the actual interface, peer, recent handshake,
   counters, and changed public egress. Usage reads real RX/TX counters.
5. Disconnect restores the normal network and cleans the temporary client
   configuration. The same account reuses its stored WireGuard identity.

The app has no automatic updater. Install a new Debian package to upgrade.
The public download catalog was verified to contain only the current ARM64
package, with exact SHA-256 and source-commit metadata. Superseded artifacts
are retained for recovery outside publicly accessible download paths. The
[publication record](releases/4.0.0+11-publication.md) records the source,
checksum, public URL checks, and recovery location.

## Next work

Complete post-reboot VPN lifecycle and final usage persistence for the
installed 4.0.0+12 candidate after sign-in. Its draft release must remain a
candidate until the remaining evidence is recorded. The separate UI preview
follows the visual-only boundaries in [ui-only-handoff.md](ui-only-handoff-2026-10-04.md)
and needs review and reconciliation with the usage candidate before integration.

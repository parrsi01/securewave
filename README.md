# SecureWave

SecureWave **4.0.0+11** is a Linux ARM64 WireGuard VPN application for Ubuntu
24.04. The installed application supports account registration, sign-in,
Connect, real WireGuard traffic and usage counters, Disconnect, Reconnect,
and logout. The user confirmed the installed application is fully functional
on 2026-10-04. Independent post-reboot release acceptance remains open.

The **4.0.0+12 usage-recording candidate** is installed locally and its usage
backend is deployed. Real Connect, traffic, Disconnect and app-crash final
reporting passed against production. The public download remains 4.0.0+11
while post-reboot checks are pending. Installed queued-report recovery through
a helper restart also passed. See the
[candidate verification record](docs/releases/4.0.0+12-verification.md).

## Download and install

Use the [official download page](https://www.securewaveapp.com/download.html)
or the [GitHub release](https://github.com/parrsi01/securewave/releases/tag/v4.0.0%2B11).
The current distributable is `securewave-vpn_4.0.0+11_arm64.deb`.
This package requires an ARM64 Linux desktop; it is not an x86-64, Windows,
macOS, Android, or iOS release.

From the directory containing the downloaded package:

```sh
sudo apt install ./securewave-vpn_4.0.0+11_arm64.deb
```

Open **SecureWave VPN** from Applications, or run `securewave-vpn`. Upgrades
use the same installation command. Disconnect before upgrading or removing
the package. The installed app runs from `/usr/lib/securewave/securewave_app`
and uses the `securewave-helper.service` systemd service.

## Changes in 4.0.0+11

- Registration explicitly uses an unauthenticated request.
- HTTP 401 messages distinguish rejected login credentials, account-creation
  authorization failures, and expired sessions.
- An expired saved session clears its token and opens **Sign in** with a
  session-expired notice, rather than sending an existing user to Create account.
- Duplicate registration recognizes production's HTTP 400 error envelope
  and explains that the account already exists.
- Regression coverage now contains 17 passing Flutter tests. Analysis and
  a live check through the actual Dart/Dio client passed: registration 201,
  login 200, and authenticated `/api/auth/me` 200. Incorrect passwords remain
  rejected with 401.

See the [release notes](docs/releases/4.0.0+11.md),
[current stack and evidence](docs/current-state.md), and
[UI-only handoff](docs/ui-only-handoff.md).

## Stack

| Component | Languages and tools | Responsibility |
| --- | --- | --- |
| Desktop app | Dart, Flutter, Dio | UI, HTTPS API requests, session and VPN orchestration |
| Linux integration | C++, GTK/GLib, Flutter method channels | Native runner and restricted local helper daemon |
| Tunnel operations | Bash, WireGuard, `wg`, `wg-quick`, `iproute2`, `iptables`, `systemd-resolved` | Tunnel lifecycle, routing, DNS, and real traffic counters |
| Local secret storage | Flutter Secure Storage, libsecret, desktop Secret Service | Access token and per-account client private key |
| Backend | Python, FastAPI, Pydantic, SQLAlchemy, psycopg2 | Authentication, account data, VPN provisioning, usage |
| Authentication | PyJWT, bcrypt/passlib | Bearer tokens and password hashing |
| Database and hosting | PostgreSQL, Hetzner, systemd, Gunicorn/Uvicorn, nginx | Production persistence, API, HTTPS, VPN infrastructure |
| Public website | HTML, CSS, JavaScript, guarded download manifest | Website and current release download selection |
| Build and release | Flutter/Dart CLI, CMake, Ninja, Debian packaging, APT, Git, GitHub CLI, SSH/SCP | Checks, ARM64 package build, versioned publishing |

The website runs in the existing production deployment; its legacy frontend
and download router are not part of this simplified source checkout. A client
release does not imply that the whole production backend has been redeployed
from the client release commit.

## Development and checks

```sh
cd securewave_app
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
SOURCE_DATE_EPOCH=0 bash scripts/build_deb.sh
```

The package builder defaults to `https://api.securewaveapp.com/api` and embeds
the version, architecture, helper contract, source commit, and tree state.
Published packages should come from a clean checkout of their release commit.
Checksums prove file integrity; the embedded source identity establishes
provenance.

For a development launch only, install the helper with
`make linux-runtime-install`, then use
`SECUREWAVE_API_BASE_URL=https://api.securewaveapp.com/api make flutter-run`.
Installed-package acceptance uses the installed desktop application.

Database credentials, JWT signing secrets, server WireGuard keys, and SSH
private keys remain outside the app and Git. The client WireGuard private key
is generated and stored locally. See [the protected boundaries](docs/DO_NOT_LOSE.md).

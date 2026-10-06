# Quick start

The tested toolchain is Python **3.12**, Flutter **3.41.4 stable** / Dart
**3.11.1**, and Ubuntu **24.04 ARM64** for the supported desktop package.

## Explore and test

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements-dev.txt
make test-backend
make test-flutter
make test-native
make check
```

The PostgreSQL tests need a disposable database and otherwise report skipped.
See [testing](docs/development/testing.md). Offline contracts need no
production credentials and do not change host routing.

## Run the backend

Create a private local environment from `.env.template`. Replace placeholders
locally with a dedicated development PostgreSQL database, independent JWT
signing secrets, and valid Fernet keys where needed. Never use production
data for tests. See [configuration](docs/development/configuration.md).

```sh
. .venv/bin/activate
make backend-run
```

Development API docs: `http://localhost:8000/api/docs`. Readiness: `/api/ready`.
A ready API still needs an authorized real WireGuard server for working VPN
provisioning.

## Run the desktop client

```sh
make flutter-get
make flutter-run
```

The default API base is `https://api.securewaveapp.com/api`. Sign in privately
in the app. Real Connect changes host networking and requires the installed
contract-15 helper and an authorized account/server.

## Build 1.0.0

After installing the [native dependencies](docs/development/releasing.md):

```sh
make linux-package
```

ARM64 output: `securewave_app/build/packaging/securewave-vpn_1.0.0_arm64.deb`.
Build from a clean detached checkout for release provenance. After reviewing
the exact package and disconnecting an active tunnel, install with:

```sh
sudo apt install ./securewave_app/build/packaging/securewave-vpn_1.0.0_arm64.deb
securewave-vpn
```

Transitioning from an older `4.0.0+…` package is a Debian version downgrade;
review that transition explicitly. The app has no automatic updater. See the
[release procedure](docs/development/releasing.md).

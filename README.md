# SecureWave

SecureWave is a Linux WireGuard VPN client backed by the existing FastAPI API, PostgreSQL database, and Hetzner-hosted VPN infrastructure.

The client supports account registration, sign-in, one VPN screen, real WireGuard connect/disconnect, session traffic totals, and logout. Flutter calls FastAPI; the Linux runner uses the installed SecureWave helper for privileged tunnel operations.

## Run

From the repository root:

    make linux-runtime-install
    SECUREWAVE_API_BASE_URL=https://api.securewaveapp.com/api make flutter-run

The helper install is needed once on a Linux machine. To build and check the Flutter client:

    cd securewave_app
    flutter pub get
    flutter analyze
    flutter test
    flutter build linux --debug

The client reads SECUREWAVE_API_BASE_URL and defaults to the production API. Flutter contains no database credentials and does not connect to PostgreSQL. See docs/DO_NOT_LOSE.md for the protected-system inventory.

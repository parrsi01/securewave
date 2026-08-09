# Linux Beta 1

## Supported target

Beta 1 is Ubuntu 24.04 LTS on ARM64 only. The current candidate has ARM64
Flutter and helper evidence; amd64 and other distributions are future work
until they have equivalent build, install, and live WireGuard evidence.

## Real flow

1. Install the single `.deb` package.
2. Launch the Flutter Linux app.
3. Register or sign in with email and password.
4. Press `CONNECT`.
5. The API issues one authenticated WireGuard profile for the configured Hetzner target.
6. The native helper validates `sw-wg.conf`, starts WireGuard, and verifies interface, route, and recent handshake evidence.
7. Press `DISCONNECT`; the helper removes the interface and owned firewall state.

The helper socket uses contract 13. Its only operations are `probe`,
`wireguard.status`, `wireguard.counters`, `wireguard.up`, `wireguard.down`,
and `wireguard.cleanup`.

## Commands

```bash
./scripts/run_linux_beta.sh backend
./scripts/run_linux_beta.sh flutter
./scripts/test_linux_beta.sh
./scripts/build_linux_deb.sh
./scripts/verify_linux_deb.sh securewave_app/build/packaging/securewave-vpn_<version>_<arch>.deb
```

`test_linux_beta.sh` is local and non-destructive. It does not deploy, publish,
push, merge, or use live credentials. Live account, clean-device install,
WireGuard egress, reconnect, restart, and cleanup acceptance remain explicit
release gates.

## Configuration

The backend uses PostgreSQL and one `WIREGUARD_SERVER_ID` in production. The
Flutter build uses one API setting: `SECUREWAVE_API_BASE_URL`. Release builds
must use HTTPS and reject localhost or placeholder URLs.

Demo mode is a separate compile-time Flutter boundary:

```bash
flutter run -d linux --dart-define=SECUREWAVE_DEMO_MODE=true
```

It is labelled `DEMO MODE · Simulated connection only`, performs no network
request, and never invokes the native helper.

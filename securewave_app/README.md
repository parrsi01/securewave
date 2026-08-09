# SecureWave Linux app

The real Linux build is a Flutter client with one authenticated WireGuard
connection. It stores one access token in Linux secure storage, obtains one
profile from the API, and hands the config to the native helper.

The UI has two product states: `CONNECT` and `DISCONNECT`. It also shows
connection health and local traffic counters. Those observers never turn a
failed health or usage read into a false connected state.

## Run

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d linux --dart-define=SECUREWAVE_API_BASE_URL=https://api.example.test/api
```

The release build uses `https://api.securewaveapp.com/api` unless an explicit
HTTPS `SECUREWAVE_API_BASE_URL` is supplied. It never falls back to localhost.

For a deterministic UI-only demo:

```bash
flutter run -d linux --dart-define=SECUREWAVE_DEMO_MODE=true
```

Demo mode is visibly labelled and selects the in-process simulated API and
WireGuard service; it cannot mark the real build connected.

The privileged helper is installed once by the Debian package. Connect and
disconnect do not ask for administrator credentials.

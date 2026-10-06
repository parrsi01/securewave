# SecureWave Linux App — 1.0.0

The current package targets Ubuntu 24.04 ARM64 and uses WireGuard.
It defaults to the live API at `https://api.securewaveapp.com/api`.

Build `securewave-vpn_1.0.0_arm64.deb` using the procedure below. Install a reviewed candidate with `sudo apt install ./<filename>`
from the directory containing it, then open **SecureWave VPN** from Applications.
The package includes the app, Flutter engine/assets, Linux helper daemon,
systemd service, desktop launcher, and icon. Flutter tooling is not required
on an end-user machine.

For development checks and a release package build:

```sh
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
SOURCE_DATE_EPOCH=0 bash scripts/build_deb.sh
```

For a development launch, run `make linux-runtime-install` and
`SECUREWAVE_API_BASE_URL=https://api.securewaveapp.com/api make flutter-run`
from the repository root. Use the installed package for release acceptance.

See [the release procedure](../docs/development/releasing.md),
[current validation](../docs/current-state.md), and
[the architecture report](../docs/research/README.md).

# Runtime inventory

## Flutter and shared state

- `securewave_app/lib/core/services/vpn_service.dart`: MethodChannel API,
  per-platform/protocol availability, runtime status, traffic counters, mock
  gating, normalized native failures.
- `securewave_app/lib/core/state/vpn_state.dart`: profile acquisition,
  connect/disconnect/reconnect intent, restored native status, counter polling,
  delta/reset handling, and timer race prevention.
- Models: `vpn_profile.dart`, `vpn_protocol.dart`, `vpn_status.dart`.
- Tests: `mock_vpn_service_test.dart`, `vpn_state_test.dart`.

## Linux

- Flutter bridge: `securewave_app/linux/runner/my_application.cc`.
- Root daemon: `securewave_app/linux/helperd/securewave_helperd.cc`.
- Narrow wrapper: `securewave_app/packaging/linux/securewave-wg-quick`.
- Contract: `securewave-wg-quick.contract` = 10.
- Service/tmpfiles: `securewave-helper.service`,
  `securewave-helper.tmpfiles`.
- Install/build: `install_linux_helper.sh`, `build_deb.sh`, Linux CMake.
- Runtime verifier: `scripts/linux_vpn_runtime_verifier.py`.
- Package workflow: `.github/workflows/linux-x64-deb-release.yml`.

Method path:

`Flutter UI -> vpnStateProvider -> ChannelVpnService -> securewave/vpn ->
/run/securewave/helper.sock -> securewave-helperd -> fixed helper operations ->
wg-quick/openvpn/nmcli/ip`

The daemon uses peer credentials, the `securewave` group, and an explicit UID
file. Request fields, operations, paths, config directives, process identity,
and helper contract are validated before root operations.

## Windows

- `securewave_app/windows/runner/flutter_window.cpp`
- WireGuard tunnel-service install/uninstall only.
- Availability rejects OpenVPN and IKEv2.
- Status requires the SecureWave tunnel service to be running.
- Byte counters are explicitly unavailable.
- Installer/build scripts exist, but no Windows build/runtime proof was run.

## macOS

- `securewave_app/macos/Runner/AppDelegate.swift`
- MethodChannel remains backward compatible.
- Availability is false; connect/disconnect return `vpn_not_configured`;
  status is disconnected; counters are unavailable.
- No Network Extension provider exists.

## Package and portable paths

- Debian package carries app, helper daemon, wrapper, contract, systemd unit,
  tmpfiles config, dependencies, post-install, pre-remove, and post-remove.
- Portable Linux tar creation strips the privileged helper payload and is
  labeled UI-only.
- Public manifest files were not changed.

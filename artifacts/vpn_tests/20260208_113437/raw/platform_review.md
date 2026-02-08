# SecureWave VPN -- Platform Integration Review

**Date:** 2026-02-08
**Reviewer:** Platform Engineer (automated audit)
**Scope:** WireGuard configuration, tunnel lifecycle, security posture, and local test feasibility across all five platforms.

---

## 1. Per-Platform Analysis

### 1.1 Linux (`securewave_app/linux/runner/my_application.cc`)

**Tunnel mechanism:** Shells out to `wg-quick up <config-path>` / `wg-quick down <config-path>` via `g_spawn_sync`. This is synchronous and blocks the Flutter UI thread during tunnel bringup.

**Config acquisition:** The Dart layer passes a WireGuard config string through the `securewave/vpn` MethodChannel with the key `"config"`. The native side writes it to `$XDG_CONFIG_HOME/securewave/securewave.conf` (permissions 0700 on the directory, default umask on the file).

**Kill switch:** NOT IMPLEMENTED. The config written by the backend includes `AllowedIPs = 0.0.0.0/0, ::/0` which routes all traffic, but there is no `PostUp`/`PostDown` iptables rule injected by the native layer. The test profile generator (`generate_test_profile.py`) does inject iptables rules via PostUp/PostDown, but the production backend `wireguard_service.py` does not. If wg-quick drops, traffic flows unprotected.

**DNS:** Delegated entirely to the config file's `DNS =` field, which wg-quick handles (typically by writing to `/etc/resolv.conf` or using `resolvconf`). No application-level DNS leak protection.

**Error handling:** Adequate. Checks for `wg-quick` availability before attempting connect/disconnect. Validates non-empty config. Reports spawn and exit-status errors back to Dart.

**Security concerns:**
- Config file is written to user config dir with no explicit `chmod 600`. Depends on umask. On shared systems, another user with read access to `~/.config/securewave/` could extract the private key.
- `g_spawn_sync` blocks the main thread. A hung wg-quick process will freeze the entire UI.
- glib compatibility shim for `g_spawn_check_wait_status` is correct and well-guarded.

**Hardcoded values:** Config file name is `securewave.conf` (constant). No hardcoded keys or endpoints.

**Build issues (known):** GTK API deprecation warnings are suppressed with `G_GNUC_BEGIN_IGNORE_DEPRECATIONS` guards. The `fl_method_channel_set_method_call_handler` signature changed in newer Flutter embedder versions; current code uses the 4-argument form which is correct for the Flutter version in use.

---

### 1.2 Windows (`securewave_app/windows/runner/flutter_window.cpp`)

**Tunnel mechanism:** Invokes `wireguard.exe /installtunnelservice "<config-path>"` to bring the tunnel up, and `wireguard.exe /uninstalltunnelservice SecureWave` to tear it down. Uses `CreateProcessW` + `WaitForSingleObject(INFINITE)`.

**Config acquisition:** Same MethodChannel pattern. Config written to `%APPDATA%\SecureWave\SecureWave.conf`.

**Kill switch:** NOT IMPLEMENTED at the application level. WireGuard for Windows may provide its own kill switch if configured, but SecureWave does not set that up programmatically.

**DNS:** Delegated to the WireGuard config's `DNS` field. The WireGuard Windows tunnel service handles DNS configuration.

**Error handling:** Good. Multiple fallback paths for finding `wireguard.exe` (env var override, `%ProgramFiles%`, `%ProgramFiles(x86)%`, hardcoded `C:\Program Files` paths). Exit code checked. Errors propagated to Dart.

**Security concerns:**
- `WaitForSingleObject(INFINITE)` on the UI thread. If `wireguard.exe` hangs, the entire application becomes unresponsive. This is the same blocking pattern as Linux.
- Config file written with `std::ofstream` -- inherits process ACLs. No explicit restrictive ACL is applied. On multi-user Windows systems, other admin users could read the private key.
- The `SECUREWAVE_WIREGUARD_PATH` environment variable override could be exploited for DLL/EXE injection if an attacker can set environment variables for the current user. However, this requires the same privilege level as the victim.

**Hardcoded values:** Tunnel service name `"SecureWave"` is hardcoded. No hardcoded keys.

---

### 1.3 Android (`SecureWaveVpnService.kt` + `MainActivity.kt`)

**Tunnel mechanism:** Uses the official WireGuard Android `GoBackend` library. Implements `android.net.VpnService`. The tunnel is started via `backend.setState(tunnel, Tunnel.State.UP, config)` and stopped via `backend.setState(tunnel, Tunnel.State.DOWN, null)`.

**Config acquisition:** Config string passed from Dart through MethodChannel, parsed with `Config.parse(StringReader(configText))`.

**Kill switch:** NOT EXPLICITLY IMPLEMENTED by SecureWave. However, Android's `VpnService` class provides system-level "Always-on VPN" and "Block connections without VPN" settings that the user can enable in system settings. The app does not programmatically enable these.

**DNS:** Handled by the WireGuard GoBackend which reads the DNS field from the parsed config and applies it through the VPN service builder.

**Error handling:** Good.
- VPN permission flow uses `ActivityResultContracts.StartActivityForResult` with proper pending-result guard against concurrent requests.
- Foreground service with notification (required for Android O+).
- `ResultReceiver` pattern to communicate success/failure back to the MethodChannel result.
- Config validation (empty check).

**Security concerns:**
- The `getParcelableExtra` call on line 46 of `SecureWaveVpnService.kt` uses the deprecated non-typed variant. On Android 13+ (API 33), this should use `getParcelableExtra(name, class)` to avoid potential class-loading attacks. In practice, this is low risk since the intent is internal.
- The notification uses `android.R.drawable.presence_online` as the icon -- this is a system drawable and works but is not branded. Minor UX issue, not a security concern.
- Foreground service type is correctly declared as `vpn` in the manifest.
- `FOREGROUND_SERVICE_SPECIAL_USE` permission is declared but `vpn` is a standard type; this extra permission may cause lint warnings.

**Hardcoded values:** Action strings use `com.example.securewave_app.vpn.*` prefix -- this needs to be updated if the application ID changes for production release. Notification ID 4201 is arbitrary but fine.

---

### 1.4 iOS (`PacketTunnelProvider.swift` + `VPNManager.swift` + `AppDelegate.swift`)

**Tunnel mechanism:** Uses Apple's Network Extension framework with `NEPacketTunnelProvider`. The `WireGuardAdapter` from the vendored `wireguard-apple` library handles the actual tunnel. The `VPNManager.swift` class wraps `NEVPNManager` to configure, save, and start/stop the tunnel.

**Config acquisition:** Config string passed from Dart through MethodChannel. The `VPNManager` stores it in `NETunnelProviderProtocol.providerConfiguration["wgConfig"]`. The `PacketTunnelProvider` reads it from `protocolConfiguration.providerConfiguration`.

**Kill switch:** NOT IMPLEMENTED. The config uses `AllowedIPs = 0.0.0.0/0, ::/0` which routes all traffic through the tunnel, but if the tunnel drops, traffic flows unprotected. iOS does support "Connect On Demand" rules through `NEVPNManager.onDemandRules`, but SecureWave does not configure them.

**DNS:** Handled by the WireGuard adapter which reads the DNS field from the config and configures the tunnel's DNS settings through the NEPacketTunnelProvider's network settings.

**Error handling:** EXCELLENT. This is the most thoroughly error-handled platform.
- `preflightError()` in VPNManager checks: simulator detection, PlugIns directory existence, PacketTunnel.appex embedding, bundle identifier match.
- `PacketTunnelProvider` has exhaustive `ParseError` handling with human-readable messages for every possible WireGuard config parse failure.
- Graceful degradation if `WireGuardKit` is not linked (compile-time `#if canImport` guards).
- Proper error wrapping with `NSUnderlyingErrorKey`.

**Security concerns:**
- Entitlements are correctly configured: both `Runner.entitlements` and `PacketTunnel.entitlements` include `com.apple.developer.networking.networkextension` with `packet-tunnel-provider`.
- The config (containing the private key) is stored in `NETunnelProviderProtocol.providerConfiguration`. This dictionary is persisted by the system in the VPN preferences plist. On a non-jailbroken device this is protected by the system keychain/sandboxing, but it is NOT stored in the Keychain proper. The vendored `wireguard-apple` library includes a `Keychain.swift` helper that is not being used by SecureWave's integration.
- The `serverAddress` field is set to the string `"SecureWave"` rather than an actual IP -- this is fine since the real endpoint is in the WireGuard config, but it means the iOS VPN settings UI will show "SecureWave" instead of the server address.

**Hardcoded values:** Provider bundle identifier is dynamically derived from `Bundle.main.bundleIdentifier + ".PacketTunnel"`. No hardcoded keys.

**Missing: `isAvailable` handler.** The iOS `AppDelegate.swift` does not handle the `"isAvailable"` method call. The Dart layer works around this by hardcoding `_nativeAvailable = true` for iOS in `_refreshNativeAvailability()`. This is fragile -- if the PacketTunnel extension is not embedded, the app will report available but fail on connect.

---

### 1.5 macOS (`securewave_app/macos/Runner/AppDelegate.swift`)

**Tunnel mechanism:** STUB ONLY. All method calls return errors.

**Config acquisition:** N/A.

**Kill switch:** N/A.

**DNS:** N/A.

**Error handling:** The stub correctly returns `FlutterError` for `connect` and `disconnect` with a clear message directing the developer to `MACOS_VPN_SETUP.md`. `isAvailable` returns `false`.

**Security concerns:**
- macOS entitlements do NOT include `com.apple.developer.networking.networkextension`. The `Release.entitlements` only has `com.apple.security.app-sandbox`. The `DebugProfile.entitlements` adds JIT and network server capabilities but no VPN entitlement.
- If someone attempts to add VPN support later, the entitlements will need to be updated.

**Assessment:** macOS is explicitly unsupported. The Dart fallback layer will use `MockVpnService` for macOS, which means the UI will show a "connected" state that is entirely simulated. This is acceptable for demo purposes but must be clearly communicated to users.

---

## 2. Cross-Platform Consistency Analysis

### 2.1 MethodChannel API Surface

| Method        | Linux | Windows | Android | iOS   | macOS |
|---------------|-------|---------|---------|-------|-------|
| `isAvailable` | Yes   | Yes     | Yes     | NO    | Yes   |
| `connect`     | Yes   | Yes     | Yes     | Yes   | Stub  |
| `disconnect`  | Yes   | Yes     | Yes     | Yes   | Stub  |

**Issue:** iOS does not implement `isAvailable`. The Dart layer compensates with a hardcoded `true` for iOS, but this creates a hidden dependency.

### 2.2 Config Delivery

All platforms receive config as a string through MethodChannel argument `"config"`. This is consistent.

### 2.3 Tunnel State Reporting

**Critical issue:** None of the native platforms report tunnel state changes back to Dart. The Dart `ChannelVpnService` sets `_status = VpnStatus.connected` immediately after the `invokeMethod('connect')` call succeeds, and `_status = VpnStatus.disconnected` after `disconnect` succeeds. There is no mechanism to detect:

- Tunnel dropping due to network change
- Server-side disconnection
- Keepalive timeout
- OS killing the VPN service (Android doze, iOS background suspension)

The UI will show "connected" indefinitely after a successful connect, even if the tunnel is dead. This is a significant state management defect.

### 2.4 Blocking UI Thread

Linux and Windows both use synchronous process execution (`g_spawn_sync`, `WaitForSingleObject(INFINITE)`) on the main thread. Android correctly uses a background executor. iOS uses async callbacks. This inconsistency means Linux and Windows will freeze during tunnel operations.

### 2.5 Protocol Support

The Dart layer accepts `VpnProtocol` (WireGuard, OpenVPN, IKEv2), but ALL native implementations only support WireGuard. The `protocol` argument is passed through the MethodChannel but ignored by every native handler. OpenVPN and IKEv2 will silently behave as WireGuard. This should either be removed from the protocol enum or properly gated with an error.

---

## 3. Security Findings Summary

| ID   | Severity | Platform      | Finding |
|------|----------|---------------|---------|
| S-01 | HIGH     | All           | No tunnel state monitoring. UI can show "connected" when tunnel is dead. |
| S-02 | HIGH     | All (backend) | Production `generate_client_config` does not include kill switch PostUp/PostDown rules. Only the test profile generator does. |
| S-03 | MEDIUM   | Linux         | Config file permissions depend on umask; no explicit `chmod 600`. Private key potentially readable by other users. |
| S-04 | MEDIUM   | Windows       | Config file inherits process ACLs; no restrictive ACL applied. |
| S-05 | MEDIUM   | iOS           | Private key stored in VPN preferences plist rather than Keychain. |
| S-06 | MEDIUM   | All (backend) | `allocate_ip` uses `user_id % 240 + 10` which means IP collisions occur when user_id > 240. Only 240 unique IPs in the /24 subnet. |
| S-07 | LOW      | All (backend) | Fallback keypair generation (when `wg` is not available) uses `secrets.token_bytes(32)` for both private and public key. The public key is not derived from the private key; it is a random blob. This produces an invalid keypair that will never establish a tunnel. |
| S-08 | LOW      | Linux/Windows | Synchronous subprocess execution blocks UI thread. |
| S-09 | LOW      | Android       | Deprecated `getParcelableExtra` without type parameter. |
| S-10 | LOW      | iOS           | Missing `isAvailable` handler; Dart hardcodes iOS as available. |
| S-11 | INFO     | macOS         | No VPN capability. Entitlements lack network extension permission. |
| S-12 | INFO     | All           | OpenVPN and IKEv2 protocol options in UI have no native backing. |

---

## 4. Local Test Mode Assessment

### 4.1 Can we test VPN tunneling without Azure backend?

**YES**, with caveats.

The test profile generator at `artifacts/vpn_tests/20260208_041545/generate_test_profile.py` can create a valid WireGuard config for local testing. The backend's `WireGuardService` supports `WG_MOCK_MODE=true` for environments without `/dev/net/tun` or the `wg` binary.

### 4.2 What is needed for a local WireGuard test

**Prerequisites:**
- `wireguard-tools` installed (`sudo apt install wireguard-tools` on Linux)
- Root/sudo access (wg-quick requires root)
- A WireGuard server (can be local or remote)

**Minimal steps for a local loopback test:**

1. **Generate test keypairs:**
   ```bash
   cd /home/sp/cyber-course/projects/securewave
   python3 artifacts/vpn_tests/20260208_041545/generate_test_profile.py \
     --server-endpoint 127.0.0.1:51820
   ```
   This writes `artifacts/vpn_tests/20260208_041545/raw/test_wg0.conf` and `test_profile_meta.json`.

2. **Set up a local WireGuard server (Linux only):**
   ```bash
   # Generate server keypair
   wg genkey | tee /tmp/sw_server_priv | wg pubkey > /tmp/sw_server_pub

   # Re-generate client config with real server pubkey
   python3 artifacts/vpn_tests/20260208_041545/generate_test_profile.py \
     --server-endpoint 127.0.0.1:51820 \
     --server-pubkey "$(cat /tmp/sw_server_pub)"

   # Create server WireGuard interface
   sudo ip link add wg-sw type wireguard
   sudo ip addr add 10.8.0.1/24 dev wg-sw
   sudo wg set wg-sw listen-port 51820 \
     private-key /tmp/sw_server_priv \
     peer "$(jq -r .client_pubkey artifacts/vpn_tests/20260208_041545/raw/test_profile_meta.json)" \
     allowed-ips 10.8.0.10/32
   sudo ip link set wg-sw up
   ```

3. **Bring up client tunnel:**
   ```bash
   sudo wg-quick up artifacts/vpn_tests/20260208_041545/raw/test_wg0.conf
   ```

4. **Verify:**
   ```bash
   ping -c 3 10.8.0.1
   sudo wg show
   ```

5. **Tear down:**
   ```bash
   sudo wg-quick down artifacts/vpn_tests/20260208_041545/raw/test_wg0.conf
   sudo ip link del wg-sw
   ```

### 4.3 Testing via the Flutter app with local backend

1. **Start local FastAPI backend:**
   ```bash
   cd /home/sp/cyber-course/projects/securewave
   WG_MOCK_MODE=true WG_ENCRYPTION_KEY="<valid-fernet-key>" \
     uvicorn main:app --host 0.0.0.0 --port 8000
   ```

2. **Point Flutter app at local backend** (update the API base URL in the app config or environment).

3. **Run Flutter app on Linux:**
   ```bash
   cd /home/sp/cyber-course/projects/securewave/securewave_app
   flutter run -d linux
   ```
   Note: The app must be run with `sudo` or the user must have WireGuard permissions for the native channel to succeed. Otherwise, the mock fallback will activate.

4. **For Android:** Run on a physical device or emulator. The GoBackend requires a real `VpnService` permission grant. Emulators do support this.

### 4.4 Testing limitations

- **iOS:** Requires a physical device with a valid provisioning profile that includes the Network Extension capability. Simulator testing will hit the `preflightError` guard and fail gracefully.
- **macOS:** No VPN capability at all. Only mock mode.
- **Windows:** Requires WireGuard for Windows to be installed and the app to run with appropriate privileges.
- **No integration test for tunnel state monitoring** exists because the native layers do not report state changes.

---

## 5. Overall Assessment

### Strengths

1. **Consistent MethodChannel contract** -- All platforms use the same `securewave/vpn` channel with the same method names and argument structure.
2. **Graceful fallback architecture** -- The `ChannelVpnService` -> `MockVpnService` chain handles missing native support cleanly.
3. **iOS error handling** is production-grade with preflight checks and exhaustive parse error coverage.
4. **Android implementation** is the most complete: proper foreground service, VPN permission flow, GoBackend integration.
5. **Backend mock mode** enables development without WireGuard infrastructure.

### Weaknesses

1. **No tunnel state monitoring** -- This is the single most critical gap. A user could believe they are protected when the tunnel has silently died.
2. **No kill switch in production configs** -- The backend's `generate_client_config` does not include PostUp/PostDown iptables rules. Only the test generator does.
3. **Blocking UI on Linux/Windows** -- Synchronous process execution will freeze the app.
4. **macOS is completely unimplemented** -- Acceptable if clearly communicated, but the mock fallback means the UI will show "connected" with no actual protection.
5. **IP allocation collision** -- The `user_id % 240` scheme cannot support more than 240 users per server.
6. **Invalid fallback keypair** -- When `wg` is not installed, the fallback generates a random public key that is not the cryptographic counterpart of the private key. Any config using these keys will fail handshake.

### Recommendations (Priority Order)

1. **Implement tunnel state monitoring** via platform-specific mechanisms:
   - Android: `Tunnel.onStateChange` callback (already wired but not reported to Dart)
   - iOS: `NEVPNConnection` status observation via `NotificationCenter`
   - Linux/Windows: Periodic `wg show` polling or interface monitoring
2. **Add kill switch rules** to the production `wireguard_service.py` config generator.
3. **Move Linux/Windows tunnel operations off the UI thread** (use isolates or platform threads).
4. **Add `isAvailable` to iOS** `AppDelegate.swift` instead of hardcoding availability in Dart.
5. **Restrict config file permissions** explicitly on Linux (chmod 600) and Windows (restrictive ACL).
6. **Fix IP allocation** to support more than 240 users (use a larger subnet or per-server allocation table).
7. **Remove or gate OpenVPN/IKEv2** protocol options since no native implementation exists.
8. **Store iOS private key in Keychain** using the existing vendored `Keychain.swift` helper.

---

## Files Reviewed

| File | Platform |
|------|----------|
| `/home/sp/cyber-course/projects/securewave/securewave_app/linux/runner/my_application.cc` | Linux |
| `/home/sp/cyber-course/projects/securewave/securewave_app/windows/runner/flutter_window.cpp` | Windows |
| `/home/sp/cyber-course/projects/securewave/securewave_app/android/app/src/main/kotlin/com/example/securewave_app/vpn/SecureWaveVpnService.kt` | Android |
| `/home/sp/cyber-course/projects/securewave/securewave_app/android/app/src/main/kotlin/com/example/securewave_app/MainActivity.kt` | Android |
| `/home/sp/cyber-course/projects/securewave/securewave_app/android/app/src/main/AndroidManifest.xml` | Android |
| `/home/sp/cyber-course/projects/securewave/securewave_app/ios/PacketTunnel/PacketTunnelProvider.swift` | iOS |
| `/home/sp/cyber-course/projects/securewave/securewave_app/ios/Runner/VPNManager.swift` | iOS |
| `/home/sp/cyber-course/projects/securewave/securewave_app/ios/Runner/AppDelegate.swift` | iOS |
| `/home/sp/cyber-course/projects/securewave/securewave_app/ios/PacketTunnel/PacketTunnel.entitlements` | iOS |
| `/home/sp/cyber-course/projects/securewave/securewave_app/ios/Runner/Runner.entitlements` | iOS |
| `/home/sp/cyber-course/projects/securewave/securewave_app/macos/Runner/AppDelegate.swift` | macOS |
| `/home/sp/cyber-course/projects/securewave/securewave_app/macos/Runner/DebugProfile.entitlements` | macOS |
| `/home/sp/cyber-course/projects/securewave/securewave_app/macos/Runner/Release.entitlements` | macOS |
| `/home/sp/cyber-course/projects/securewave/securewave_app/lib/core/services/vpn_service.dart` | Dart (all) |
| `/home/sp/cyber-course/projects/securewave/securewave_app/lib/core/models/vpn_status.dart` | Dart (all) |
| `/home/sp/cyber-course/projects/securewave/securewave_app/lib/core/models/vpn_protocol.dart` | Dart (all) |
| `/home/sp/cyber-course/projects/securewave/services/wireguard_service.py` | Backend |
| `/home/sp/cyber-course/projects/securewave/artifacts/vpn_tests/20260208_041545/generate_test_profile.py` | Test tooling |

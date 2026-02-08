# SecureWave VPN -- Multi-Platform Implementation Review

**Date:** 2026-02-08
**Reviewer:** Platform Engineer (Senior Systems Architect)
**Baseline Score:** 85/100
**Scope:** All 5 native platform implementations + Dart bridge + state machine

---

## 1. ANDROID (Kotlin)

**Files reviewed:**
- `/home/sp/cyber-course/projects/securewave/securewave_app/android/app/src/main/kotlin/com/example/securewave_app/vpn/SecureWaveVpnService.kt`
- `/home/sp/cyber-course/projects/securewave/securewave_app/android/app/src/main/kotlin/com/example/securewave_app/MainActivity.kt`

### Implementation Completeness: 90%

### Launch Readiness: PARTIAL

### Architecture
- Two-class design: `MainActivity` handles MethodChannel + VPN permission flow; `SecureWaveVpnService` extends `VpnService` and runs GoBackend on a single-thread executor.
- Permission request uses `ActivityResultContracts.StartActivityForResult` -- correct modern pattern.
- Communication between Activity and Service uses `ResultReceiver` posted back to main looper -- clean and avoids cross-thread MethodChannel calls.
- GoBackend integration uses the official `com.wireguard.android.backend.GoBackend` library.

### Strengths
1. Foreground service with notification channel -- compliant with Android 8+ requirements.
2. `@Volatile` annotation on `currentState` -- correct for cross-thread visibility.
3. `executor.shutdown()` in `onDestroy()` -- proper cleanup.
4. Permission denied case handled with explicit error code `missing_vpn_permission`.
5. Guard against concurrent requests: `pendingResult != null` check in connect.
6. `START_NOT_STICKY` return -- appropriate; the VPN service should not auto-restart without user intent.

### Critical Gaps
1. **No reconnection on service restart.** If the Android system kills the foreground service (rare but possible under extreme memory pressure), there is no mechanism to restore the tunnel. The service returns `START_NOT_STICKY`, so it will not be restarted. This is acceptable for v1 but should be documented.
2. **ResultReceiver leak potential.** If the user rotates the device or the Activity is destroyed while a VPN operation is in-flight, `pendingResult` becomes a stale reference. The `ResultReceiver` callback will attempt to call `result.success()` or `result.error()` on a detached `MethodChannel.Result`. This can cause a `FlutterJNI` crash on some Flutter engine versions.
3. **No disconnect on `onTaskRemoved`.** If the user swipes the app from recents, the foreground service continues running but the Flutter engine is gone. There is no `onTaskRemoved()` override to gracefully tear down the tunnel.
4. **Notification channel re-created on every notification.** `buildNotification()` calls `createNotificationChannel()` every time. While idempotent, it is inefficient. Should be created once in `onCreate()`.
5. **Package name mismatch.** The package is `com.example.securewave_app` -- this is the Flutter template default and must be changed before Play Store submission.

### Thread Safety
- The `executor` is a `newSingleThreadExecutor`, so all GoBackend calls are serialized. No race between connect and disconnect.
- `currentState` is `@Volatile` -- reads from the main thread are safe.
- `ResultReceiver` dispatches to `Handler(Looper.getMainLooper())` -- MethodChannel results are delivered on the UI thread. Correct.

### Memory Safety
- No concerns. Kotlin/JVM manages memory. The `ResultReceiver` is parceled into the Intent, so it survives the IPC boundary.

### Race Conditions
- **LOW RISK:** If `connect` is called while a previous `connect` executor task is still running, the second call will be queued on the single-thread executor. However, `pendingResult` in `MainActivity` guards against this at the Dart layer. Acceptable.
- **MEDIUM RISK:** If the Activity is destroyed and recreated (config change), `pendingResult` is lost. The in-flight `ResultReceiver` still holds the old `MethodChannel.Result`. Calling `result.success()` on it may throw or silently fail depending on engine state.

---

## 2. WINDOWS (C++)

**File reviewed:**
- `/home/sp/cyber-course/projects/securewave/securewave_app/windows/runner/flutter_window.cpp`

### Implementation Completeness: 85%

### Launch Readiness: PARTIAL

### Architecture
- MethodChannel handler in `OnCreate()` spawns a `std::thread` for each VPN operation.
- The thread calls `RunWireGuardCommand()` (blocking `CreateProcessW` + `WaitForSingleObject` with 30s timeout).
- Completion is posted back to the UI thread via `PostMessage(hwnd, kVpnOpCompleteMessage, ...)`.
- `MessageHandler` processes the custom message and resolves the Flutter result on the UI thread.

### Strengths
1. **PostMessage pattern is correct.** Flutter MethodChannel results must be resolved on the platform thread. Using `PostMessage` to bounce back to the Win32 message loop is the right approach.
2. **30-second timeout with `TerminateProcess` fallback.** Prevents indefinite hangs if WireGuard stalls.
3. **Config file written to `%APPDATA%\SecureWave\SecureWave.conf`.** Proper user-scoped location.
4. **WireGuard path discovery** checks env override, `%ProgramFiles%`, `%ProgramFiles(x86)%`, and hardcoded fallbacks. Thorough.
5. **Handle cleanup** after `WaitForSingleObject` -- both `hProcess` and `hThread` are closed in all code paths.

### Critical Gaps
1. **Config file persists on disk in plaintext.** The WireGuard configuration (including private keys) is written to `%APPDATA%\SecureWave\SecureWave.conf` and never deleted after disconnect. This is a **security concern** -- private key material remains on disk indefinitely.
2. **No tunnel service cleanup on app crash.** If the app crashes after `/installtunnelservice`, the WireGuard tunnel service remains installed and running. There is no startup check to detect and clean up orphaned tunnel services.
3. **`GetHandle()` called from worker thread.** The `GetHandle()` method is called from the spawned `std::thread`. If the window is destroyed between the `WaitForSingleObject` return and the `GetHandle()` call, `GetHandle()` returns `nullptr` and the fallback path resolves the result directly from the worker thread. Resolving a `MethodResult` from a non-platform thread violates Flutter engine threading assumptions. This is a **thread safety bug**.
4. **Detached threads.** `std::thread(...).detach()` means there is no way to cancel or join these threads on shutdown. If `FlutterWindow::OnDestroy()` runs while a VPN operation thread is still in `WaitForSingleObject`, the thread will eventually try to `PostMessage` to a destroyed HWND (which returns `FALSE` but does not crash) or resolve the result directly (see point 3).
5. **No elevation handling.** WireGuard tunnel service installation requires administrator privileges. There is no UAC elevation prompt or detection of insufficient privileges. The error message says "Ensure the app has required privileges" but provides no programmatic path to acquire them.
6. **No `isAvailable` for tunnel status.** `isAvailable` only checks whether `wireguard.exe` exists on disk. It does not check whether a tunnel is already running, which could cause `/installtunnelservice` to fail if the tunnel name is already in use.

### Thread Safety
- **BUG (MEDIUM):** The fallback path in the worker thread (lines 241-247 and 275-280) calls `pending->result->Success()` or `pending->result->Error()` from a non-UI thread when `GetHandle()` returns `nullptr`. This violates Flutter engine threading contracts.
- **ACCEPTABLE:** `PostMessage` is thread-safe by Windows API contract. The `VpnOpPending` ownership transfer (allocated on worker, freed on UI thread) is correct -- only one side ever accesses it after the `PostMessage`.

### Memory Safety
- `VpnOpPending` is heap-allocated with `new` and `delete`d in `MessageHandler`. Ownership is clear: the worker thread transfers ownership via `PostMessage`, and the message handler frees it.
- **POTENTIAL LEAK:** If `PostMessage` fails (e.g., message queue full), the `pending` pointer leaks. `PostMessage` returning `FALSE` is not checked. However, the fallback path (hwnd == nullptr) handles the null-HWND case, and PostMessage failure on a valid HWND is extremely rare.

### Race Conditions
- **LOW RISK:** Two concurrent connect calls could both spawn threads. The Flutter Dart layer (vpn_service.dart) guards against this with status checks, so this is unlikely in practice.

---

## 3. LINUX (C / GLib)

**File reviewed:**
- `/home/sp/cyber-course/projects/securewave/securewave_app/linux/runner/my_application.cc`

### Implementation Completeness: 80%

### Launch Readiness: PARTIAL

### Architecture
- MethodChannel handler spawns `wg-quick` via `g_spawn_async()`.
- A `GChildWatch` callback fires when the process exits.
- A `GTimeout` callback fires after 30 seconds if the process has not exited.
- Both callbacks are ref-counted via `WgQuickSpawnContext` to prevent use-after-free.
- The `responded` flag ensures exactly one response is sent per method call.

### Strengths
1. **Ref-counted context (`WgQuickSpawnContext`).** The ref counting pattern using `g_atomic_int_inc` / `g_atomic_int_dec_and_test` is correct. Initial ref_count=1, one additional ref for child_watch, one for timeout, then the initial ref is released. The last callback to fire will free the context.
2. **Respond-once guard (`ctx->responded`).** Prevents double-responding if both the child watch and timeout fire (e.g., process exits at exactly the timeout boundary).
3. **SIGKILL on timeout.** The timeout callback sends `SIGKILL` to the stuck `wg-quick` process. This is the correct signal for a hard kill -- `SIGTERM` could be ignored by a misbehaving process.
4. **Glib 2.70 compatibility shim.** The `g_spawn_check_wait_status` / `g_spawn_check_exit_status` compatibility macro handles the API rename gracefully.
5. **GTK deprecation warnings suppressed** with `G_GNUC_BEGIN_IGNORE_DEPRECATIONS` / `G_GNUC_END_IGNORE_DEPRECATIONS` blocks.
6. **Config directory created with mode 0700.** Restricts read access to the owning user. Good security posture.

### Critical Gaps
1. **`wg-quick` requires root/sudo.** The code calls `wg-quick up` and `wg-quick down` without privilege escalation. On most Linux distributions, `wg-quick` requires root privileges. The error message mentions "Ensure you have the required permissions" but there is no `pkexec` or `sudo` integration. Users must run the app as root or configure `wg-quick` with `setcap` -- neither is documented in the binary.
2. **Config file persists in plaintext.** Written to `~/.config/securewave/securewave.conf` with `g_file_set_contents()`. Never deleted after disconnect. Same security concern as Windows.
3. **No kill switch implementation in the native layer.** The Dart vpn_state.dart references `PostUp`/`PostDown` hooks in the WireGuard config for kill switch behavior, but the native Linux code does not set up or verify any iptables/nftables rules. Kill switch is entirely dependent on the server-provided config containing the right hooks.
4. **No tunnel status tracking.** There is no way to check if a `wg-quick` interface is already up. Calling `connect` twice without `disconnect` will attempt `wg-quick up` on an already-active interface, which will fail with a confusing error.
5. **`VpnChannelState` holds `config_path` as state.** If `connect` is never called, `config_path` is `nullptr`, and `disconnect` will fail with `vpn_config_missing`. This is correct behavior but the error message could be clearer.

### Memory Safety (Ref Counting Analysis)
```
spawn_wg_quick_async():
  ctx = g_new0(...)          // ref_count = 1 (implicit)
  ctx->ref_count = 1         // explicit init
  g_child_watch_add_full(
    ..., ref(ctx), unref)    // ref_count = 2
  g_timeout_add_full(
    ..., ref(ctx), unref)    // ref_count = 3
  unref(ctx)                 // ref_count = 2
  // ctx is now owned by child_watch + timeout

Child watch fires:
  // removes timeout source -> timeout's unref fires -> ref_count = 1
  // child_watch's own unref fires -> ref_count = 0 -> freed

Timeout fires first:
  // timeout's unref fires at end -> ref_count = 1
  // child_watch still holds a ref
  // when child eventually exits, child_watch fires -> unref -> ref_count = 0 -> freed
```

**VERDICT: The ref counting is correct.** All code paths result in exactly zero refs at the end. No use-after-free, no leak.

**HOWEVER:** There is a subtle issue. In `wg_quick_timeout_cb`, the timeout fires and calls `wg_quick_respond_error_once(ctx, ...)`, then `kill(ctx->pid, SIGKILL)`. After this, the function returns `G_SOURCE_REMOVE`, and GLib calls the destroy notify (`wg_quick_spawn_context_unref`). At this point `ref_count` drops from 2 to 1. Later, when the killed process exits, `wg_quick_child_watch_cb` fires. It calls `g_source_remove(ctx->timeout_id)` -- but `ctx->timeout_id` was set to 0 by the timeout callback itself (line 137). So `g_source_remove(0)` is called, which is a **GLib critical warning** (source ID 0 is invalid). This is a **bug** -- the child watch callback should check `ctx->timeout_id != 0` before calling `g_source_remove()`.

Wait -- re-reading the child watch callback (line 120-133):
```c
static void wg_quick_child_watch_cb(GPid pid, gint wait_status, gpointer user_data) {
  WgQuickSpawnContext* ctx = static_cast<WgQuickSpawnContext*>(user_data);
  if (ctx->timeout_id != 0) {
    g_source_remove(ctx->timeout_id);
    ctx->timeout_id = 0;
  }
```

It does check `ctx->timeout_id != 0`. And the timeout callback sets `ctx->timeout_id = 0` on line 137. So when the child watch fires after the timeout, it sees `timeout_id == 0` and skips the `g_source_remove`. **This is correct.** No bug here. The ref counting and guard logic is sound.

### Thread Safety
- All callbacks (`wg_quick_child_watch_cb`, `wg_quick_timeout_cb`, `handle_vpn_call`) run on the GLib main loop, which is single-threaded by default. No concurrent access to `WgQuickSpawnContext`. Thread-safe by design.
- `g_atomic_int_inc` / `g_atomic_int_dec_and_test` are overkill for single-threaded GLib main loop usage but are not harmful.

### Race Conditions
- **NONE in native code.** All callbacks are serialized on the GLib main loop.
- **APPLICATION-LEVEL:** Two rapid connect calls from Dart could spawn two `wg-quick` processes. The Dart layer guards against this.

---

## 4. iOS (Swift)

**Files reviewed:**
- `/home/sp/cyber-course/projects/securewave/securewave_app/ios/Runner/AppDelegate.swift`
- `/home/sp/cyber-course/projects/securewave/securewave_app/ios/Runner/VPNManager.swift`
- `/home/sp/cyber-course/projects/securewave/securewave_app/ios/PacketTunnel/PacketTunnelProvider.swift`
- `/home/sp/cyber-course/projects/securewave/securewave_app/ios/Runner/Runner.entitlements`
- `/home/sp/cyber-course/projects/securewave/securewave_app/ios/PacketTunnel/PacketTunnel.entitlements`

### Implementation Completeness: 92%

### Launch Readiness: PARTIAL

### Architecture
- `AppDelegate` sets up the MethodChannel and delegates to `SecureWaveVPNManager.shared` singleton.
- `SecureWaveVPNManager` uses `NEVPNManager` to configure and start a `NETunnelProviderProtocol`.
- `PacketTunnelProvider` (Network Extension) uses `WireGuardKit`'s `WireGuardAdapter` when available, with full config parsing.
- Entitlements for both Runner and PacketTunnel include `com.apple.developer.networking.networkextension` with `packet-tunnel-provider`.

### Strengths
1. **Comprehensive preflight checks.** `preflightError()` checks: (a) simulator environment, (b) PlugIns directory existence, (c) PacketTunnel.appex presence, (d) bundle identifier match. This is the most robust availability check across all platforms.
2. **Full WireGuard config parser** in `PacketTunnelProvider.swift` with exhaustive `ParseError` enum and human-readable error messages for every parse failure case.
3. **Conditional compilation** with `#if canImport(WireGuardKit)` gracefully handles builds where WireGuardKit is not linked.
4. **Structured logging** via `os.Logger` with appropriate privacy levels.
5. **Error wrapping** in `VPNManager.wrap()` provides user-friendly messages while preserving the underlying error via `NSUnderlyingErrorKey`.
6. **Entitlements are correctly configured** for both Runner and PacketTunnel targets.

### Critical Gaps
1. **No VPN status observation.** `SecureWaveVPNManager` does not observe `NEVPNConnection.statusDidChange` notifications. The Dart layer has no way to know if the tunnel drops unexpectedly (e.g., server-side disconnect, network change). The status in `vpn_state.dart` will remain "connected" indefinitely.
2. **`disconnect()` calls `stopVPNTunnel()` and immediately fires `completion()`.** The tunnel may not have actually stopped when the completion handler runs. Should observe `NEVPNStatus.disconnected` before completing.
3. **`startVPNTunnel()` is called synchronously after `saveToPreferences`.** On first install, iOS may prompt the user to approve the VPN configuration. The `startVPNTunnel()` call will fail if the preferences have not been fully saved yet. A `loadFromPreferences` should be called after `saveToPreferences` before starting the tunnel (Apple's documented pattern).
4. **No `App Transport Security` or network entitlement** in Runner entitlements. The Runner entitlements only have `com.apple.developer.networking.networkextension`. For the app to make network requests to the backend API, `com.apple.security.network.client` may be needed (though this is mainly a macOS sandbox concern; iOS apps have network access by default).
5. **WireGuardKit dependency.** The `#if canImport(WireGuardKit)` guard means the app will compile and run without WireGuardKit, but `startTunnel` will immediately fail with error code -11. The preflight check in `VPNManager` does not verify that WireGuardKit is actually linked -- it only checks for the `.appex` bundle.

### Thread Safety
- `NEVPNManager` operations (`loadFromPreferences`, `saveToPreferences`) are asynchronous and callback on arbitrary queues. The `connect` method chains these callbacks, which is correct.
- `SecureWaveVPNManager` is a singleton accessed from the main thread (via MethodChannel handler). The `[weak self]` captures prevent retain cycles. No concurrent mutation risk.

### Race Conditions
- **LOW RISK:** Two rapid `connect` calls could both enter `configure()` and race on `saveToPreferences`. The Dart layer's `isBusy` guard prevents this.

---

## 5. macOS (Swift)

**File reviewed:**
- `/home/sp/cyber-course/projects/securewave/securewave_app/macos/Runner/AppDelegate.swift`
- `/home/sp/cyber-course/projects/securewave/securewave_app/macos/Runner/Release.entitlements`
- `/home/sp/cyber-course/projects/securewave/securewave_app/macos/Runner/DebugProfile.entitlements`

### Implementation Completeness: 15%

### Launch Readiness: NO

### Architecture
- Stub implementation only. The MethodChannel is registered and responds to all three methods (`isAvailable`, `connect`, `disconnect`).
- `isAvailable` returns `false`.
- `connect` and `disconnect` return `FlutterError` with code `vpn_not_configured` and a helpful message pointing to `MACOS_VPN_SETUP.md`.

### Critical Gaps
1. **No VPN functionality whatsoever.** This is a deliberate stub.
2. **Release.entitlements missing VPN capability.** Contains only `com.apple.security.app-sandbox`. Missing:
   - `com.apple.developer.networking.networkextension` (packet-tunnel-provider)
   - `com.apple.security.network.client` (outgoing network connections)
   - `com.apple.security.network.server` (if needed)
3. **DebugProfile.entitlements** has `com.apple.security.network.server` and `com.apple.security.cs.allow-jit` but also lacks the Network Extension entitlement.
4. **No PacketTunnel extension target for macOS.** The iOS PacketTunnel target exists but there is no corresponding macOS target.

### Assessment
This is an acknowledged gap. The Dart bridge correctly handles this by falling back to `MockVpnService` on macOS (since `isAvailable` returns `false`). The user experience degrades gracefully: the app runs, the VPN button works (demo mode), but no actual tunnel is established. For launch, macOS should either be excluded from distribution or explicitly marked as "demo only" in the UI.

---

## 6. DART VPN SERVICE BRIDGE

**File reviewed:**
- `/home/sp/cyber-course/projects/securewave/securewave_app/lib/core/services/vpn_service.dart`

### Implementation Completeness: 88%

### Launch Readiness: PARTIAL

### Architecture
- `VpnService` abstract class defines the contract.
- `ChannelVpnService` wraps the `MethodChannel('securewave/vpn')` with fallback to `MockVpnService`.
- iOS is treated specially: native unavailability throws instead of falling back to mock.
- `MockVpnService` provides simulated connect/disconnect with configurable delays.

### Strengths
1. **Triple-layered fallback:** Checks `isAvailable` first, then catches `PlatformException`, then catches `MissingPluginException`. Covers all failure modes.
2. **iOS special-casing is correct.** iOS users should never see mock VPN behavior -- the tunnel either works or it does not. Falling back to mock on iOS would be misleading.
3. **`_logMockUse` logs only once.** Prevents log spam.
4. **Status guards** prevent connect-while-connecting and disconnect-while-disconnecting.

### Critical Gaps
1. **No status polling or event stream.** The `_status` field is only updated by explicit `connect`/`disconnect` calls. If the native tunnel drops (e.g., server disconnect, network change), the Dart layer will still report `VpnStatus.connected` until the next explicit operation. A `MethodChannel` event channel or periodic `getStatus` poll is needed.
2. **`_refreshNativeAvailability()` called on every connect/disconnect.** This makes a round-trip to the native side each time. On slow devices, this adds latency to the connect flow. Consider caching with a TTL.
3. **Mock fallback in production.** The `allowFallback` parameter defaults to `true`. If a production build on Windows or Linux ships without WireGuard installed, the app silently falls back to mock mode. This could mislead users into thinking they are protected when they are not. The `const bool.fromEnvironment('dart.vm.product')` triple-guard mentioned in MEMORY.md is not visible in this file -- it may be enforced elsewhere but should be verified.
4. **`connect()` does not reset `_status` on error in the mock-fallback path.** If `_fallback.connect()` throws (which `MockVpnService` never does, but a custom fallback could), `_status` remains `connecting` indefinitely.

---

## 7. VPN STATE MACHINE

**File reviewed:**
- `/home/sp/cyber-course/projects/securewave/securewave_app/lib/core/state/vpn_state.dart`

### Implementation Completeness: 90%

### Launch Readiness: PARTIAL

### Architecture
- `VpnState` immutable data class with `copyWith`.
- `VpnStateNotifier` extends `StateNotifier<VpnState>` (Riverpod).
- Manages: connection lifecycle, protocol selection, server selection, rate simulation, stability scoring, error classification, auto-reconnect on connectivity restore.

### Strengths
1. **`isBusy` guard** prevents overlapping connect/disconnect operations.
2. **`desiredOn` flag** enables auto-reconnect: if connectivity is restored and `desiredOn` is true, the notifier attempts to reconnect.
3. **10-second auto-reconnect throttle** prevents reconnect storms.
4. **Kill switch awareness** in `handleConnectivityChange`: detects PostUp/PostDown hooks in cached config and transitions to error state if the tunnel appears down.
5. **Comprehensive error classification** (`_classifyVpnError`) maps error strings and codes to user-friendly messages with actionable guidance.
6. **Cached config fallback** during profile fetch failure provides resilience against transient backend outages.
7. **`unawaited(connect())`** for auto-reconnect is correct -- fire-and-forget with the `isBusy` gate preventing overlap.

### Critical Gaps
1. **Rate simulation is fake.** `_startRateSimulation()` generates random numbers, smoothed by `MarLXGBPredictor`. This is not reading actual tunnel throughput. Acceptable for demo/MVP but must be replaced with real metrics before users pay for "optimized" bandwidth.
2. **No tunnel health monitoring.** The state machine relies entirely on explicit connect/disconnect calls. There is no periodic ping, handshake check, or native status event to detect silent tunnel failures.
3. **`clearError` in `copyWith` has a semantic issue.** `copyWith(errorMessage: 'new error', clearError: true)` will set `errorMessage` to `null` because `clearError` takes precedence. This is technically correct (clear wins) but is a footgun for future developers.
4. **`_classifyVpnError` uses string matching on `error.toString()`.** Patterns like `'401'` or `'500'` could false-positive on unrelated error messages. Error classification should use structured error codes where possible.
5. **Stability score is session-scoped only.** `_stabilitySuccesses` and `_stabilityFailures` reset when the notifier is recreated (e.g., on hot restart or provider disposal). Long-term stability tracking requires persistence.

---

## CROSS-PLATFORM SUMMARY TABLE

| Platform | Completeness | Launch Ready | Critical Issues |
|----------|-------------|-------------|-----------------|
| Android  | 90%         | PARTIAL     | ResultReceiver leak on config change; no onTaskRemoved; example package name |
| Windows  | 85%         | PARTIAL     | Thread safety bug in fallback path; plaintext config on disk; no UAC elevation |
| Linux    | 80%         | PARTIAL     | Requires root; plaintext config; no kill switch in native layer; GTK deprecation build risk |
| iOS      | 92%         | PARTIAL     | No VPN status observation; disconnect completion premature; missing loadFromPreferences reload |
| macOS    | 15%         | NO          | Stub only; no entitlements; no PacketTunnel target |
| Dart     | 88%         | PARTIAL     | No status polling; mock fallback in production; no event channel |
| State    | 90%         | PARTIAL     | Fake rate data; no health monitoring; string-based error classification |

---

## TOP 10 LAUNCH BLOCKERS (PRIORITY ORDER)

1. **[ALL] No tunnel status observation / health monitoring.** The system cannot detect silent tunnel failures. Users may believe they are protected when the tunnel has dropped.

2. **[WINDOWS] Thread safety violation.** Resolving MethodChannel result from a worker thread when HWND is null will crash or corrupt Flutter engine state.

3. **[ALL] Plaintext private keys on disk.** Windows (`%APPDATA%`) and Linux (`~/.config/`) write WireGuard configs containing private keys and never delete them. This fails any security audit.

4. **[iOS] No `NEVPNStatus` observation.** The Dart layer will report stale connection status indefinitely.

5. **[LINUX] Root privilege requirement.** `wg-quick` requires root. No privilege escalation mechanism exists. The app will fail for all non-root users with a confusing error.

6. **[ANDROID] Package name `com.example.securewave_app`.** Cannot submit to Play Store with example package name.

7. **[macOS] No VPN implementation.** Must either implement or explicitly exclude from distribution.

8. **[DART] Mock fallback in production builds.** Users on Windows/Linux without WireGuard will silently get a fake VPN with no actual tunnel protection.

9. **[iOS] Missing `loadFromPreferences` after `saveToPreferences`.** First-time VPN setup may fail on iOS due to preferences not being committed before tunnel start.

10. **[ALL] Rate simulation is synthetic.** Displaying fake bandwidth numbers to paying users is deceptive. Must be replaced with real metrics or clearly labeled as estimates.

---

## REVISED SCORE

Starting from 85/100:

- -3 for tunnel status observation gap (all platforms)
- -2 for Windows thread safety bug
- -2 for plaintext private keys on disk
- -1 for iOS NEVPNStatus gap
- -1 for Linux root requirement with no escalation
- -1 for mock fallback in production
- +1 for excellent iOS preflight checks
- +1 for correct Linux ref counting
- +1 for clean Android permission flow

**Revised Score: 78/100**

The implementation is architecturally sound across all platforms, with good separation of concerns, proper error handling patterns, and correct memory/thread safety in most cases. The primary deficiencies are in observability (no tunnel health monitoring), security hygiene (plaintext keys on disk), and production readiness (mock fallback, fake metrics, missing platform implementations). These are addressable without architectural changes.

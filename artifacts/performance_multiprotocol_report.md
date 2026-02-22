# Performance Multiprotocol Report

Date (UTC): 2026-02-22
Branch: `release/multiprotocol-live-only`

## Scope

Performance and memory optimization pass focused on:
- multiprotocol client control-plane overhead (WireGuard / OpenVPN / IKEv2),
- native capability/runtime check overhead on desktop bridges,
- unnecessary UI rebuilds in connection status feedback,
- repeatable headless profiling in CI-friendly test runs.

This report is evidence-based from local profiling runs in the current CLI/Linux environment. Full Windows/macOS desktop runtime profiling is listed as a manual follow-up section.

## What Changed

### 1) Native capability / availability caching (`ChannelVpnService`)
File: `securewave_app/lib/core/services/vpn_service.dart`

- Added short-lived in-memory caches for:
  - `getCapabilities()` results (default TTL: 3s)
  - native `isAvailable` checks (default TTL: 2s)
- Connect/disconnect now reuse fresh cached results instead of repeating native checks inside the same operation window.
- Cache invalidates on native-unavailable errors / missing plugin paths.

Impact:
- Reduces method-channel calls and desktop subprocess/path-check work during startup, settings rendering, and connect/disconnect.

### 2) Connect path overhead reduction (`VpnStateNotifier`)
File: `securewave_app/lib/core/state/vpn_state.dart`

- Reused a single `SecureStorage` instance in the notifier.
- Added in-memory cached `DeviceIdentity.load()` future to avoid repeated secure-storage reads on every connect.
- Throttled optional metrics snapshot fetches (`fetchVpnMetricsSnapshot`) to avoid repeated background requests during rapid connect/disconnect bursts.

Impact:
- Reduces async work and network/JSON overhead on reconnect loops without changing tunnel behavior.

### 3) UI rebuild reduction (`StatusDisplay`)
File: `securewave_app/lib/screens/home/widgets/status_display.dart`

- Removed timer ticking during `disconnecting` (no time-based UI was visible there).
- Reduced connect-progress tick cadence to 2s (connected timer remains 1s).
- Preserved progress clarity while lowering rebuild frequency in the hot status widget.

Impact:
- Fewer unnecessary rebuilds during connect/disconnect transitions.

### 4) Performance profiling tests (repeatable)
Files:
- `securewave_app/test/performance/channel_vpn_service_cache_test.dart`
- `securewave_app/test/performance/multiprotocol_performance_profile_test.dart`

- Added cache hit/miss verification and `PERF ...` log output.
- Added headless "first interactive frame proxy" benchmark (home VPN UI widgets).
- Added control-plane connect/disconnect latency benchmark across WireGuard/OpenVPN/IKEv2 using the existing state-machine harness.

## Profiling Runs (Executed)

### A) Performance test suite (headless)
Command:

```bash
cd securewave_app
flutter test test/performance/channel_vpn_service_cache_test.dart test/performance/multiprotocol_performance_profile_test.dart -r expanded
```

Observed `PERF` outputs (latest run):

- `channel_vpn_service_cache`
  - `startup_isAvailable_calls=1`
  - `cached_getCapabilities_calls=1`
  - `cached_isAvailable_calls=1`
- `channel_vpn_service_cache_after_ttl`
  - `getCapabilities_calls=2` (refresh after TTL confirmed)
- `cold_start_interactive_frame_proxy_ms=151.871`
- WireGuard control-plane latency (avg / p95)
  - connect: `0.497 ms` / `0.616 ms`
  - disconnect: `0.161 ms` / `0.221 ms`
- OpenVPN control-plane latency (avg / p95)
  - connect: `0.548 ms` / `1.044 ms`
  - disconnect: `0.150 ms` / `0.235 ms`
- IKEv2 control-plane latency (avg / p95)
  - connect: `0.482 ms` / `0.634 ms`
  - disconnect: `0.149 ms` / `0.216 ms`

Interpretation:
- Control-plane overhead is sub-millisecond in the local harness across all three protocols.
- OpenVPN shows slightly higher p95 in the harness (still very low), consistent with larger profile payload handling.

### B) CPU / Memory profile of the performance suite
Command:

```bash
cd securewave_app
/usr/bin/time -v flutter test test/performance/channel_vpn_service_cache_test.dart test/performance/multiprotocol_performance_profile_test.dart -r expanded
```

Results:
- Wall time: `2.12s`
- User CPU time: `2.69s`
- System CPU time: `0.59s`
- CPU utilization: `154%`
- Max RSS: `436232 kB` (~`426 MiB`)
- Exit status: `0`

Notes:
- This is framework/test-runner memory, not the release desktop app process RSS.
- Use platform-specific release profiling (below) for production runtime memory baselines.

## Objective Status

1. Cold start target `< 1.0s` first interactive frame
- `PASS (headless proxy)` with `151.871 ms` for the home VPN interaction widget set (`ConnectionRing` + `StatusDisplay`) in a test harness.
- `NOT YET FULLY VALIDATED` for packaged Linux/Windows/macOS release binaries in this environment.

2. Reduce unnecessary rebuilds
- `PASS (implemented)` by removing `disconnecting` timer ticks and lowering connect-progress tick cadence.
- This directly reduces `StatusDisplay` rebuild frequency during transitional states.

3. Minimize native subprocess overhead
- `PASS (implemented + tested)` via `ChannelVpnService` capability/availability caches.
- Cache test confirms repeated capability/availability checks are not re-issued within TTL.

4. Optimize thread usage
- `PARTIAL PASS (implemented)` via reduced background async churn:
  - cached device identity future,
  - metrics snapshot throttling / in-flight dedupe.
- Full native thread profiling requires platform-specific tools (see manual commands).

5. Resource profiling for connections (latency, CPU, memory)
- `PASS (headless control-plane + test-runner CPU/RSS)` with per-protocol latency and timed suite CPU/RSS captured.
- `PARTIAL` for live tunnel data-plane CPU/memory across all desktop platforms (manual runs required).

## Platform-Specific Manual Profiling (Recommended)

### Linux (desktop release build)

```bash
cd securewave_app
flutter build linux --release
perf stat -d ./build/linux/x64/release/bundle/securewave_app
```

If `perf` unavailable, fallback:

```bash
/usr/bin/time -v ./build/linux/x64/release/bundle/securewave_app
```

To inspect child process overhead during OpenVPN/IKEv2:

```bash
strace -f -tt -e trace=process ./build/linux/x64/release/bundle/securewave_app
```

### Windows

Use PowerShell (Release build):

```powershell
Measure-Command { .\build\windows\x64\runner\Release\securewave_app.exe }
Get-Process securewave_app, openvpn -ErrorAction SilentlyContinue | Select-Object Name,CPU,PM,WS
```

For deeper profiling:
- Windows Performance Recorder (CPU Usage, File I/O, Process Lifetime)
- Windows Performance Analyzer for analysis

### macOS

Release/preview build:

```bash
open build/macos/Build/Products/Release/SecureWave.app
```

Profile with Instruments:
- Time Profiler
- Allocations
- System Trace

CLI fallback snapshot:

```bash
ps -axo pid,pcpu,pmem,rss,comm | grep -i SecureWave
```

## Risks / Tradeoffs Introduced

- Capability/availability caches are intentionally short-lived. Runtime changes inside the TTL window may take up to 2-3s to reflect.
- Metrics snapshot throttling can skip some rapid transition snapshots; this reduces noise/overhead but slightly lowers observability granularity during reconnect storms.
- The cold-start metric is a headless UI proxy, not a full release-binary first-frame measurement.

## Files Changed (this pass)

- `securewave_app/lib/core/services/vpn_service.dart`
- `securewave_app/lib/core/state/vpn_state.dart`
- `securewave_app/lib/screens/home/widgets/status_display.dart`
- `securewave_app/test/performance/channel_vpn_service_cache_test.dart`
- `securewave_app/test/performance/multiprotocol_performance_profile_test.dart`
- `artifacts/performance_multiprotocol_report.md`

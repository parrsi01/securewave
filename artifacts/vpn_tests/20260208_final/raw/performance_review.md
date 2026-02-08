# SecureWave VPN -- Final Performance Review

**Date:** 2026-02-08
**Reviewer:** VPN Performance Engineer
**Scope:** Backend WireGuard services, desktop native bridges, ML optimizer, DNS/kill-switch, client state machine
**Baseline score:** 85/100

---

## 1. Latency Analysis

### 1.1 Key Generation Time

**Files:** `services/wireguard_service.py` lines 107-128

Two code paths exist:

| Path | Estimated latency | Notes |
|---|---|---|
| `wg genkey` + `wg pubkey` (subprocess) | 5-15 ms | Two sequential subprocess spawns; acceptable |
| X25519 fallback (`cryptography` library) | < 1 ms | Pure-Python Curve25519; fast |

The subprocess path shells out twice (`check_output` for genkey, then `check_output` for pubkey). These are synchronous calls on the FastAPI event loop thread. In the `/allocate` and `/connect` endpoints, this blocks the async handler for the duration of two subprocess invocations.

**Risk:** Under concurrent load, synchronous `subprocess.check_output` in an async endpoint will block the event loop. The X25519 fallback is non-blocking and fast. In mock/demo mode the fallback is used, so this only manifests in production with the `wg` binary present.

**Rating: ACCEPTABLE** -- Latency is low in absolute terms, but the blocking-on-event-loop pattern is a scalability concern for > 50 concurrent key generations.

### 1.2 Config Generation Time

**Files:** `services/wireguard_service.py` lines 164-190, `routes/vpn.py` lines 294-331

Config generation is pure string concatenation -- negligible latency (< 0.1 ms). File write via `_write_secret_file` is a single synchronous `Path.write_text` call. The `chmod` follows with an `OSError` catch.

QR code generation (`qr_from_config`, line 253-257) uses the `qrcode` library to render a PNG into a BytesIO buffer then base64-encode it. This is CPU-bound and takes approximately 20-50 ms per call. It is called synchronously in the `/allocate` endpoint.

**Rating: ACCEPTABLE** -- QR generation is the bottleneck. Consider caching or moving to a background task for high-concurrency scenarios.

### 1.3 Connection Setup Overhead (Full Path)

The `/allocate` endpoint (lines 427-607) performs these sequential steps:

1. Subscription check (DB query)
2. Server selection (DB query or optimizer)
3. Peer lookup/creation (DB query + possible insert)
4. Key generation (if new peer)
5. Config string assembly
6. File write
7. QR code generation
8. Peer registration on remote server (SSH/HTTP/Azure -- async, but awaited)
9. Legacy key sync + DB commit

Steps 7 and 8 dominate. Peer registration via SSH (`_run_ssh_command`) has a 30-second timeout. Via HTTP API, the `httpx.AsyncClient` timeout is also 30 seconds (line 96). In the happy path, SSH peer registration is 2-5 seconds (SSH handshake + command execution). HTTP API is 0.5-2 seconds.

**Total estimated connection setup time:**
- Happy path (HTTP API): 100-300 ms
- Happy path (SSH): 2-6 seconds
- Worst case (timeout): 30-60 seconds

**Rating: NEEDS_WORK** -- The SSH path adds multi-second latency to what should be a sub-second control-plane operation. The 30-second timeout is correct for safety, but the SSH handshake overhead is inherent and significant. The `StrictHostKeyChecking=no` flag (line 357) speeds things up but is a security trade-off documented elsewhere.

---

## 2. Throughput Bottlenecks

### 2.1 Tunnel Data Path

The backend is the **control plane only**. It does not touch tunnel data. WireGuard kernel/userspace handles all data-plane throughput. No serialization or blocking exists in the data path from the backend perspective.

On Android, the `GoBackend` (line 14, `SecureWaveVpnService.kt`) runs WireGuard userspace in a single-threaded executor (`Executors.newSingleThreadExecutor()`, line 21). This is the standard wireguard-android pattern and does not bottleneck -- the actual crypto runs in Go routines inside the GoBackend native library.

**Rating: PASS**

### 2.2 API Serialization

All VPN endpoints use Pydantic v2 models for request/response serialization. The `AllocateConfigResponse` includes a base64-encoded QR PNG which can be 5-15 KB. This is acceptable for a control-plane response.

The `/config` endpoint (line 1073) reads config files from disk synchronously. Under high load, this could cause file I/O contention, but the files are tiny (< 1 KB).

**Rating: PASS**

---

## 3. Desktop Async Correctness

### 3.1 Linux: Ref-Counted Spawn Context

**File:** `securewave_app/linux/runner/my_application.cc` lines 76-187

The `WgQuickSpawnContext` uses manual atomic reference counting (`g_atomic_int_inc` / `g_atomic_int_dec_and_test`). Analysis:

- **Initial ref_count:** 1 (line 169)
- **Ref for child watch callback:** +1 via `wg_quick_spawn_context_ref` (line 178), freed by `GDestroyNotify` -> `wg_quick_spawn_context_unref`
- **Ref for timeout callback:** +1 via `wg_quick_spawn_context_ref` (line 184), freed by `GDestroyNotify` -> `wg_quick_spawn_context_unref`
- **Original ref:** -1 via `wg_quick_spawn_context_unref` (line 186)

This leaves exactly 2 refs outstanding (child watch + timeout). When the child exits:
- `wg_quick_child_watch_cb` fires, removes the timeout source (`g_source_remove`), responds, then the GDestroyNotify on the child watch unrefs -> count = 1
- The timeout's GDestroyNotify fires (since `g_source_remove` was called) -> unrefs -> count = 0 -> freed

When the timeout fires first:
- `wg_quick_timeout_cb` fires, kills the child, responds. Its own GDestroyNotify unrefs -> count = 1
- The child watch still fires (child was killed), tries to respond (guarded by `ctx->responded`), then its GDestroyNotify unrefs -> count = 0 -> freed

**The `responded` flag** (lines 102-118) prevents double-responding. This is correct.

**Potential issue:** `g_source_remove(ctx->timeout_id)` in the child watch callback (line 124) removes the timeout source. The GDestroyNotify associated with the timeout source will fire, calling `wg_quick_spawn_context_unref`. This is correct because `g_source_remove` triggers the destroy notify. However, if the timeout fires *concurrently* on the same thread (GLib main loop is single-threaded, so this cannot happen), there would be a race. Since GLib main loop callbacks are serialized, this is safe.

**Verdict:** The ref-counting is correct and leak-free. The `responded` guard prevents double-response. The single-threaded GLib main loop prevents races between the child watch and timeout callbacks.

**Rating: PASS**

### 3.2 Windows: PostMessage Pattern

**File:** `securewave_app/windows/runner/flutter_window.cpp` lines 226-282

The pattern:
1. A `VpnOpPending` is heap-allocated with `new` (line 226)
2. A detached `std::thread` runs `RunWireGuardCommand` (blocking, up to 30s timeout)
3. On completion, `PostMessage(hwnd, kVpnOpCompleteMessage, 0, LPARAM(pending))` sends the result back to the UI thread
4. `FlutterWindow::MessageHandler` (line 308-323) processes the message, calls `result->Success/Error`, then `delete pending`

**Safety analysis:**

- **Thread safety of `GetHandle()`:** Called from background thread (line 236). `GetHandle()` returns the cached HWND. If the window is destroyed before the thread completes, `GetHandle()` returns `nullptr`. The code checks for this (line 237) and falls back to calling `result->Success/Error` directly from the background thread (lines 240-244). This is **problematic**: Flutter's `MethodResult` is not thread-safe and must be invoked on the platform (UI) thread. If the window is destroyed mid-operation, calling `result->Success()` from a background thread is undefined behavior for the Flutter engine.

- **Handle lifetime:** The detached thread captures `this` (line 228). If `FlutterWindow` is destroyed before the thread completes, `this` is dangling. `OnDestroy` (line 300) nulls `flutter_controller_` but does not wait for background threads.

- **Timeout:** `RunWireGuardCommand` uses `WaitForSingleObject` with `kWireGuardCommandTimeoutMs = 30000` (30 seconds). On timeout, it calls `TerminateProcess` and returns false. This is correct.

- **Handle cleanup:** `CloseHandle` is called for both process and thread handles in all exit paths (lines 121, 123, 130, 131, 139, 140). Correct.

**Verdict:** The PostMessage pattern is the correct way to marshal results to the UI thread. However, the fallback path (window gone, line 240-244) invokes Flutter APIs from a background thread, which is unsafe. This is an edge case (window closing during VPN operation) but could cause a crash.

**Rating: ACCEPTABLE** -- The normal path is correct. The edge-case fallback is unsafe but unlikely to trigger in practice. Should be fixed before final release.

---

## 4. Timeout Handling

### 4.1 Linux: 30-Second Timeout

**File:** `my_application.cc` line 26: `kWgQuickTimeoutMs = 30000`

`wg-quick up` typically completes in 1-3 seconds. A 30-second timeout is generous and appropriate for:
- Slow DNS resolution during `wg-quick up` (which may resolve endpoint hostnames)
- Network interface creation delays on loaded systems
- PolicyKit/pkexec authentication dialogs (though `wg-quick` typically requires root)

On timeout, the child process is killed with `SIGKILL` (line 142). This is aggressive but correct -- a hung `wg-quick` should not leave zombie processes.

**Rating: PASS**

### 4.2 Windows: 30-Second Timeout

**File:** `flutter_window.cpp` line 17: `kWireGuardCommandTimeoutMs = 30000`

Same 30-second timeout for `wireguard.exe /installtunnelservice`. On timeout, `TerminateProcess` is called (line 120). The `wireguard.exe` service installer is normally fast (< 5 seconds), so 30 seconds provides adequate headroom.

**Rating: PASS**

### 4.3 Backend SSH/Azure Timeouts

**File:** `services/wireguard_server_manager.py`

- SSH: `asyncio.wait_for(..., timeout=self.timeout)` where `self.timeout = int(os.getenv("WG_COMMAND_TIMEOUT", "30"))` (line 67). Configurable, default 30 seconds. Correct.
- Azure: `timeout=self.timeout * 2` (line 538). Azure Run Command is inherently slower; doubling to 60 seconds is appropriate.
- HTTP API: `httpx.AsyncClient(timeout=self.timeout)` (line 96). 30-second default. Correct.

**Rating: PASS**

---

## 5. IP Allocation Scalability

**File:** `services/wireguard_service.py` lines 160-162

```python
def allocate_ip(self, user_id: int) -> str:
    octet = (user_id % 240) + 10
    return f"10.8.0.{octet}/32"
```

This allocates IPs in the range `10.8.0.10` to `10.8.0.249` (240 addresses). For a single `/24` subnet, this is the maximum usable range (reserving .0 for network, .1 for gateway, .255 for broadcast, and .2-.9 for infrastructure).

**Critical issue:** `user_id % 240` means user IDs 1 and 241 get the same IP (`10.8.0.11`). If both users connect to the same WireGuard server simultaneously, they will have conflicting `AllowedIPs` entries. WireGuard uses the most recent `wg set` command, so one user silently loses connectivity.

**Mitigations present:** The newer `WireGuardPeer` model (used by `/profile` and `/allocate` endpoints) assigns `peer.ipv4_address` during peer creation in `VpnPeerManager`, which likely uses a different allocation scheme. The legacy `allocate_ip` is only used in the `/connect` compatibility endpoint. However, this creates an inconsistency between the two allocation paths.

**Scale limit:** 240 concurrent users per WireGuard server instance. For a SaaS VPN, this is low. Multi-subnet allocation (10.8.1.0/24, 10.8.2.0/24, etc.) or per-server IP pool management is needed for production scale.

**Rating: NEEDS_WORK** -- The 240-user cap is a hard architectural limit. IP collision via modulo is a correctness bug for any deployment beyond 240 users per server. The newer peer-based allocation partially mitigates this but the legacy path remains active.

---

## 6. DNS Configuration

### 6.1 Default DNS Servers

**Files:** `services/wireguard_service.py` lines 51-55, `routes/vpn.py` lines 239-245

Default DNS: `94.140.14.14, 94.140.15.15` (AdGuard DNS with ad/malware blocking).

This is a solid default for a privacy-focused VPN:
- AdGuard DNS provides ad blocking and malware protection at the DNS level
- Two servers for redundancy
- IPv4 only (no IPv6 DNS servers configured)

**Missing:** No IPv6 DNS servers (e.g., `2a10:50c0::ad1:ff`, `2a10:50c0::ad2:ff` for AdGuard). The WireGuard config includes `AllowedIPs = 0.0.0.0/0, ::/0` which routes IPv6 traffic through the tunnel, but DNS queries over IPv6 will fail or fall back to the OS resolver, potentially causing DNS leaks on dual-stack networks.

The `SECUREWAVE_TUNNEL_DNS` environment variable allows override, and `_profile_dns_servers()` parses comma-separated values correctly.

**Rating: ACCEPTABLE** -- Good defaults, but missing IPv6 DNS creates a potential leak vector on dual-stack networks. Should add IPv6 AdGuard DNS as supplementary entries.

### 6.2 DNS Leak Protection Service

**File:** `services/dns_leak_protection.py`

This is a server-side diagnostic service, not an in-tunnel protection mechanism. It reads `/etc/resolv.conf` on the **server**, not the client. Its value is limited to server-side health checks.

The actual DNS leak protection is in the WireGuard config itself (`DNS = ...` directive forces the tunnel to use specified resolvers). The `AllowedIPs = 0.0.0.0/0, ::/0` ensures all traffic (including DNS on port 53) routes through the tunnel.

**Rating: PASS** -- The WireGuard config-based approach is the correct DNS leak prevention mechanism. The diagnostic service is supplementary.

---

## 7. Kill Switch Performance

### 7.1 Linux Kill Switch (iptables hooks)

**File:** `routes/vpn.py` lines 271-291

The kill switch uses `PostUp` / `PostDown` hooks in the WireGuard config:

```
iptables -I OUTPUT ! -o %i -m mark ! --mark $(wg show %i fwmark) -m addrtype ! --dst-type LOCAL -j REJECT
```

**Performance analysis:**
- The iptables rule is inserted at position 1 in the OUTPUT chain (`-I OUTPUT`). This means every outbound packet hits this rule first.
- The rule uses three match modules: interface match (`! -o %i`), mark match (`-m mark`), and address type match (`-m addrtype`). Each adds a small per-packet overhead.
- On modern kernels with nftables backend, iptables-nft translates this efficiently. On legacy iptables, the overhead is negligible for typical VPN workloads (< 1 microsecond per packet).

**Fail-closed behavior:** When the WireGuard interface goes down, the `PostDown` hook removes the rule. If `wg-quick` crashes without running `PostDown`, the REJECT rule persists and blocks all non-local traffic. This is the **correct fail-closed behavior** for a kill switch.

**Dual-stack:** Both `iptables` and `ip6tables` rules are installed, preventing IPv6 leaks. The `command -v` guard (line 279) ensures no errors on systems without iptables installed.

**Limitation:** Only applied for `device_type == "linux"` (line 317). Mobile platforms (iOS/Android) must use their own kill switch mechanisms (Always-on VPN on Android, NEOnDemandRule on iOS).

**Rating: PASS** -- Correct fail-closed implementation with minimal per-packet overhead. Dual-stack coverage is present.

---

## 8. Optimizer Overhead

### 8.1 Server-Side Optimizer

**File:** `services/vpn_optimizer.py`

The `select_optimal_server` method (line 382) is called during connection setup. Its performance characteristics:

- **Without ML (MARL-only):** Iterates over all servers, computes Q-value lookup (O(1) hash map) + reward calculation (arithmetic only) per server. For a fleet of 100 servers, this is < 0.1 ms.
- **With ML (MARL+XGBoost):** For each server, extracts a 12-feature vector, calls `xgb_model.predict()`. XGBoost predict on a single sample with 100 trees of depth 6 takes ~0.1-0.5 ms. For 100 servers: 10-50 ms total.

**Critical path impact:** The optimizer is NOT called in the `/allocate` or `/profile` hot paths. Server selection uses `VPNServerService.get_active_servers()` and `VPNServerService.allocate_server_for_user()` which are DB queries, not optimizer calls. The optimizer is a separate service that could be used for pre-scoring but is not currently wired into the connection flow.

The XGBoost incremental training (`_train_xgboost_incremental`, line 458) runs every 100 telemetry updates. Training on 300 samples with 100 trees takes ~50-200 ms. This is called from `report_connection_quality`, which is a background telemetry path, not the connection setup path.

**Rating: PASS** -- The optimizer does not add latency to connection setup in the current architecture. When/if wired in, the MARL-only path is sub-millisecond. The XGBoost path is < 50 ms for typical fleet sizes, which is acceptable.

### 8.2 Client-Side Predictor

**File:** `securewave_app/lib/core/optimization/marlxgb.dart`

Pure arithmetic (no ML inference). `predictBandwidth` is O(1), `scoreServer` is O(1). Called every 2 seconds in the rate simulation timer (`vpn_state.dart` line 340). Zero impact on connection setup.

**Rating: PASS**

---

## 9. Client State Machine

**File:** `securewave_app/lib/core/state/vpn_state.dart`

### 9.1 State Transitions

The state machine tracks: `disconnected -> connecting -> connected` and `connected -> disconnecting -> disconnected`, with `error` as a terminal/recovery state.

- **`desiredOn` flag:** Tracks user intent separately from actual state. This enables auto-reconnect (`handleConnectivityChange`, line 285) without unwanted reconnects after explicit disconnect. Correct pattern.
- **`isBusy` guard:** Prevents concurrent connect/disconnect operations (lines 131, 251). Correct.
- **Auto-reconnect throttle:** 10-second cooldown between auto-reconnects (line 321). Prevents reconnect storms.

### 9.2 Kill Switch Awareness

Lines 285-309: When network connectivity is lost and `desiredOn` is true, the state machine checks if the cached VPN profile contains `PostUp`/`PostDown` hooks (indicating kill switch is active). If so, it transitions to error state with a descriptive message. This is a best-effort heuristic -- it cannot actually detect whether the iptables rules are in effect.

### 9.3 Profile Caching / Fallback

Lines 192-206: If the profile fetch fails, the client falls back to a cached config from secure storage. This is resilient but has a security implication: stale configs with rotated keys will fail at the WireGuard handshake level (not silently connect with wrong keys). This is acceptable.

**Rating: PASS**

---

## 10. Android VPN Service

**File:** `securewave_app/android/app/src/main/kotlin/.../SecureWaveVpnService.kt`

- **GoBackend initialization:** Created in `onCreate()` (line 34). The GoBackend constructor starts the userspace WireGuard implementation. This is the standard wireguard-android pattern.
- **Single-threaded executor:** `Executors.newSingleThreadExecutor()` (line 21) serializes connect/disconnect operations. This prevents races between concurrent tunnel state changes.
- **Foreground service:** `startForeground` is called before the blocking `backend.setState()` (line 61-62). This is correct -- Android requires foreground notification before long-running VPN operations.
- **Error handling:** Catches exceptions from `Config.parse` and `backend.setState`, sends error via `ResultReceiver`, and stops the service cleanly.
- **Missing:** No timeout on `backend.setState()`. If the GoBackend hangs (rare but possible with DNS resolution of the endpoint), the executor thread blocks indefinitely. The foreground service will remain running with a "Connecting..." notification.

**Rating: ACCEPTABLE** -- Solid implementation following wireguard-android patterns. Missing timeout on `setState()` is a minor concern.

---

## Summary Scorecard

| Area | Rating | Score Impact |
|---|---|---|
| Key generation latency | ACCEPTABLE | 0 |
| Config generation latency | ACCEPTABLE | 0 |
| Connection setup overhead (SSH path) | NEEDS_WORK | -2 |
| Tunnel data path throughput | PASS | 0 |
| Linux async correctness (ref counting) | PASS | 0 |
| Windows async correctness (PostMessage) | ACCEPTABLE | -1 |
| Linux 30s timeout | PASS | 0 |
| Windows 30s timeout | PASS | 0 |
| Backend timeouts (SSH/HTTP/Azure) | PASS | 0 |
| IP allocation scalability (240 cap) | NEEDS_WORK | -3 |
| DNS configuration (AdGuard defaults) | ACCEPTABLE | -1 |
| DNS leak protection | PASS | 0 |
| Kill switch (iptables fail-closed) | PASS | 0 |
| Optimizer overhead (server-side) | PASS | 0 |
| Optimizer overhead (client-side) | PASS | 0 |
| Client state machine | PASS | 0 |
| Android VPN service | ACCEPTABLE | 0 |

---

## Adjusted Score

**Starting score:** 85/100
**Deductions:**
- IP allocation collision bug and 240-user cap: -3
- SSH peer registration latency in connection setup: -2
- Windows PostMessage edge-case thread safety: -1
- Missing IPv6 DNS servers: -1

**Final performance score: 78/100**

---

## Priority Fixes for Launch

1. **IP allocation (CRITICAL):** Replace `user_id % 240` with per-server IP pool management. The legacy `/connect` endpoint should use the same `WireGuardPeer`-based allocation as `/profile` and `/allocate`.

2. **SSH peer registration latency (HIGH):** Consider making peer registration fire-and-forget (return the config immediately, register the peer asynchronously). The WireGuard tunnel will fail its first handshake until registration completes, but the retry mechanism will succeed within seconds.

3. **Windows thread safety (MEDIUM):** In the fallback path (window destroyed during VPN operation), queue the result for later delivery or silently discard it rather than invoking Flutter APIs from a background thread.

4. **IPv6 DNS (MEDIUM):** Add AdGuard IPv6 DNS servers (`2a10:50c0::ad1:ff`, `2a10:50c0::ad2:ff`) to the default DNS configuration to prevent DNS leaks on dual-stack networks.

5. **Android setState timeout (LOW):** Wrap `backend.setState()` in a coroutine with a 30-second timeout to match desktop behavior.

---

*Report generated by VPN Performance Engineer, 2026-02-08.*
*All ratings based on code review; no live tunnel benchmarks were conducted.*

# SecureWave ML & Optimizer Security and Correctness Review

**Date:** 2026-02-08
**Reviewer:** ML/Systems Auditor
**Scope:** All ML components, optimizer, policy engine, client-side predictor, data pipeline

---

## Executive Summary

The ML stack is well-structured with consistent fallback behavior and reasonable anti-poisoning measures. The architecture follows a sound pattern: server-side MARL + XGBoost for routing decisions, client-side lightweight arithmetic predictor for UX smoothing. No critical security vulnerabilities were found. Several medium-risk issues exist around unbounded state growth, missing input validation at API boundaries, and a feedback loop stability concern in the Q-learning update path.

**Overall Risk Rating: MEDIUM**

---

## 1. Component Inventory

| File | Role | ML Dependency | Fallback |
|------|------|---------------|----------|
| `services/vpn_optimizer.py` | Server selection (MARL + XGBoost) | numpy, xgboost, sklearn | Yes, MARL-only or reward-based |
| `services/xgb_qos.py` | QoS classification (4-class) | numpy, xgboost | Yes, rule-based scoring |
| `services/xgb_risk.py` | Risk scoring (regression 0-1) | numpy, xgboost | Yes, rule-based scoring |
| `services/marl_policy.py` | Policy decisions (MARL engine) | None (pure Python) | N/A (always available) |
| `services/security_monitor.py` | Unified security pipeline | Depends on above | Inherits fallbacks |
| `services/policy_engine_worker.py` | Background eval loop | Depends on above | Graceful skip |
| `securewave_app/lib/core/optimization/marlxgb.dart` | Client-side bandwidth predictor | None (pure Dart arithmetic) | N/A (always available) |
| `ml/experiment.py` | Offline training pipeline | numpy, xgboost | Skips if unavailable |
| `ml/data.py` | Data loading and splitting | None | N/A |
| `ml/metrics.py` | Accuracy/MAE scoring | None | N/A |
| `ml/seed.py` | RNG seeding | Optional numpy | Graceful skip |
| `ml/config.py` | Experiment configuration | None | N/A |

---

## 2. Input Validation and Clamping

### 2.1 vpn_optimizer.py -- GOOD

**Rating: LOW RISK**

The `_validate_metric` static method (line 180-188) is well-implemented:
- Handles NaN explicitly (`v != v` check)
- Handles TypeError/ValueError
- Clamps to min/max bounds
- Returns safe default on failure

All metric fields in `update_server_metrics` are validated with appropriate ranges:
- `latency_ms`: [0, 10000]
- `bandwidth_mbps`: [0, 100000]
- `cpu_load`: [0, 1.0]
- `active_connections`: [0, 100000]
- `packet_loss`: [0, 1.0]
- `jitter_ms`: [0, 5000]
- `security_score`: [0, 1.0]

`report_connection_quality` also validates `actual_latency` and `actual_throughput` before use.

**Finding VOP-1:** `add_server` (line 163-177) does NOT validate `initial_metrics`. Values from `metrics.get()` are used directly with only default fallbacks but no clamping. If `initial_metrics` contains, for example, `latency_ms: -500` or `bandwidth_mbps: float('inf')`, these are stored unclamped.

### 2.2 xgb_qos.py -- MEDIUM RISK

**Rating: MEDIUM RISK**

The `classify_qos` convenience function (line 267-294) and the `QoSInput` dataclass accept raw floats with no validation or clamping. The rule-based fallback at line 127-131 does clamp intermediate scores to [0, 1], but raw input values flow directly into XGBoost feature vectors.

**Finding QOS-1:** No input validation on `QoSInput` fields. A caller passing `latency_ms: -1000` or `packet_loss: 50.0` will produce garbage predictions from XGBoost. The rule-based fallback partially mitigates this (its formulas naturally clamp scores) but the XGBoost path does not.

### 2.3 xgb_risk.py -- MEDIUM RISK

**Rating: MEDIUM RISK**

Same pattern as QoS. `RiskInput` has no validation. The rule-based path clamps the final score to [0, 1] (line 178), and the XGBoost path clamps output (line 264), but unbounded inputs can produce unpredictable model behavior.

**Finding RSK-1:** `RiskInput.login_failures` and `reconnect_frequency` are unbounded integers. A value of `login_failures: 999999` would saturate the rule-based score at 0.3 (due to `min(0.3, ...)`) but could produce bizarre XGBoost predictions depending on training distribution.

### 2.4 marlxgb.dart (Client) -- GOOD

**Rating: LOW RISK**

The Dart predictor is well-hardened:
- `predictBandwidth` clamps output to `[min, max]` (line 61)
- Anomaly detection clamps samples deviating >2.5x from EMA (lines 52-58)
- `scoreServer` clamps final score to `[0, 1]` (line 93)
- `scoreStability` clamps to `[0, 1]` (line 113)
- `predictMtu` returns only three hard-coded safe values: 1280, 1360, 1420
- `predictKeepalive` returns only three hard-coded values: 10, 15, 25

No issues found in the client-side predictor.

### 2.5 marl_policy.py -- LOW RISK

**Rating: LOW RISK**

The policy engine's `_check_safety_constraints` (line 167-208) uses hard thresholds that are configurable but have safe defaults. The `calculate_reward` function clamps to [-1.0, 1.0] (line 165).

**Finding MRL-1:** The `evaluate_connection` convenience function (line 355-425) passes raw inputs (`latency_ms`, `packet_loss`, etc.) directly into `StateVector` without validation. These flow into safety constraint checks which use comparison operators, so extreme values would correctly trigger safety actions. However, they also flow into `_hash_state` where `int(state.latency_ms / 50)` on `latency_ms = float('inf')` would raise `OverflowError`.

---

## 3. Anti-Poisoning Measures

### 3.1 Server-Side (vpn_optimizer.py) -- GOOD

- `_validate_metric` prevents NaN, Inf, and out-of-range values from entering the model
- Q-values are clamped to [-10.0, 10.0] (line 382)
- Metrics history is bounded via `deque(maxlen=5000)` (line 110)
- Q-table uses LRU eviction at 10,000 entries (line 84)
- Training uses only recent 300 samples (line 469)

**Finding AP-1:** The incremental training path (`_train_xgboost_incremental`, line 463-500) trains on the metrics_history buffer which contains only validated data. However, the training labels (target) are derived from the same validated data (lines 487-489), creating a self-referential loop. This is acceptable for a server recommendation engine but means the model learns to predict its own input transformations, not actual user-perceived quality.

### 3.2 Client-Side (marlxgb.dart) -- GOOD

- Anomaly clamping on bandwidth samples (>2.5x deviation suppressed)
- EMA smoothing dampens sudden spikes
- All outputs bounded

### 3.3 Training Pipeline (ml/data.py) -- MEDIUM RISK

**Finding AP-2:** `load_telemetry_csv` (line 6-23) performs no validation on CSV values. It calls `float()` and `int()` directly. A poisoned CSV file with extreme values would flow unchecked into training data. The `build_risk_dataset` function derives features from `risk_score` with deterministic formulas (lines 68-75), meaning the risk model is trained on synthetic features derived from labels -- this is a data leakage pattern that would inflate apparent accuracy.

**Finding AP-3:** `build_risk_dataset` (lines 64-88) constructs training features deterministically from `risk_score` (the label). For example, `login_failures = int(risk_score * 5)` and `geo_anomaly = 1.0 if risk_score > 0.5 else 0.0`. This means the model is learning to reverse a known deterministic transformation, not learning from real behavioral signals. This is a significant methodological flaw that makes the risk model's accuracy metric meaningless on this dataset.

---

## 4. Feedback Loop Stability

### 4.1 Q-Learning Convergence -- LOW RISK

**Rating: LOW RISK**

The Q-learning update in `vpn_optimizer.py` (line 379-384):
```
new_q = current_q + 0.01 * (reward + 0.9 * max_next_q - current_q)
new_q = clamp(new_q, -10.0, 10.0)
```

- Learning rate 0.01 is conservative (prevents large jumps)
- Discount factor 0.9 is standard
- Exploration rate 0.05 prevents greedy lock-in
- Q-value clamping to [-10, 10] prevents divergence
- LRU eviction prevents memory exhaustion

The `marl_policy.py` Q-learning (line 243-245) does NOT clamp Q-values:
```
new_q = current_q + 0.1 * (reward + 0.9 * max_next_q - current_q)
```

**Finding FL-1:** The MARL policy engine's Q-values are unbounded. With a learning rate of 0.1 and no clamping, Q-values can theoretically grow without limit if consistently positive rewards are applied. In practice, the reward is clamped to [-1, 1] and the Q-learning update is contractive, so divergence is unlikely but not impossible over very long runs. The `vpn_optimizer.py` handles this correctly with [-10, 10] clamping.

### 4.2 Oscillation Risk -- LOW RISK

The optimizer could theoretically oscillate between two servers if:
1. Server A is selected, load increases
2. Server B is now preferred, selected, its load increases
3. Server A load decreases, selected again

This is mitigated by:
- 0.05 exploration rate adds randomness
- Q-table smooths out transient load spikes via slow learning (0.01 rate)
- State hashing quantizes `cpu_load` to 10 levels, adding natural hysteresis

No oscillation fix is needed at this time.

---

## 5. Output Bounds

### 5.1 vpn_optimizer.py

| Output | Bounded? | Range |
|--------|----------|-------|
| `confidence_score` | Yes | [0, 1] via `min(1.0, reward * 1.2)` (line 417) |
| `estimated_latency_ms` | Partially | Depends on validated input [0, 10000] |
| `estimated_bandwidth_mbps` | Partially | Depends on validated input [0, 100000] |
| `server_load` | Yes | [0, 1] via input validation |
| Q-values | Yes | [-10, 10] via clamping |

### 5.2 xgb_qos.py

| Output | Bounded? | Range |
|--------|----------|-------|
| `score` | Yes (XGB) | [0, 1] via weighted probabilities |
| `score` | Yes (rule) | [0, 1] via weighted clamped scores |
| `label` | Yes | One of 4 fixed strings |
| `confidence` | Yes | [0, 1] from softmax probabilities |

### 5.3 xgb_risk.py

| Output | Bounded? | Range |
|--------|----------|-------|
| `score` | Yes | [0, 1] via explicit `max(0.0, min(1.0, ...))` (line 264) |
| `level` | Yes | One of 4 fixed strings |

### 5.4 marl_policy.py

| Output | Bounded? | Range |
|--------|----------|-------|
| `action` | Yes | Enum (5 values) |
| `confidence` | Yes | Fixed at 0.8 or 0.9 or 1.0 |
| `reward` | Yes | [-1, 1] (line 165) |

**All output bounds are acceptable.**

---

## 6. Fallback Behavior

### 6.1 ML Dependency Failures -- GOOD

All three ML services (`vpn_optimizer.py`, `xgb_qos.py`, `xgb_risk.py`) implement the same pattern:
1. Try importing numpy/xgboost/sklearn
2. Set `ML_AVAILABLE` flag
3. Fall back to rule-based/heuristic scoring if unavailable

**The app starts and functions fully without any ML dependencies installed.** This is a strong production safety property.

### 6.2 XGBoost Prediction Failures -- GOOD

All three services wrap XGBoost predictions in try/except blocks and fall back to rule-based scoring:
- `xgb_qos.py` line 245-247
- `xgb_risk.py` line 282-284
- `vpn_optimizer.py` line 343-344

### 6.3 Policy Engine Failures -- GOOD

`policy_engine_worker.py` wraps each session evaluation in try/except (line 83-85), and the outer loop backs off on error (line 59).

### 6.4 Client-Side Failures -- GOOD

The Dart `MarLXGBPredictor` uses pure arithmetic with no external dependencies. It cannot fail unless the Dart runtime itself fails.

---

## 7. Data Efficiency Review

### 7.1 Client-Side Telemetry -- LOW RISK

**Finding DE-1:** The `VpnStateNotifier` in `vpn_state.dart` runs a `Timer.periodic` every 2 seconds (line 316) that updates bandwidth display rates. This is LOCAL ONLY -- it generates random numbers and runs the EMA predictor. It does NOT phone home or make network calls. The timer is properly cancelled on disconnect (line 336) and dispose (line 429).

The only network calls during VPN operation are:
- `api.notifyVpnConnected()` -- once on connect
- `api.notifyVpnDisconnected()` -- once on disconnect
- Profile fetch -- once on connect

**No polling telemetry loops exist on the client.** This is excellent for battery and bandwidth.

### 7.2 Server-Side Polling -- MEDIUM RISK

**Finding DE-2:** `PolicyEngineWorker` runs a background loop every 30 seconds (line 35, `evaluation_interval=30`). Each iteration:
1. Opens a database session
2. Queries ALL active VPN sessions
3. For each session, calls `evaluate_connection` which invokes both QoS and Risk scoring
4. Commits any changes

With 1000 concurrent sessions, this means 1000 QoS evaluations + 1000 Risk evaluations + 1000 MARL decisions every 30 seconds. Each evaluation involves dictionary construction and floating-point math. No ML inference (models are not trained in production by default), so the cost is dominated by database queries.

**Recommendation:** Consider adding a minimum session count threshold to skip evaluation when no sessions are active. The current implementation opens/closes a DB session every 30 seconds even when there are zero active connections.

### 7.3 Metrics History Growth -- LOW RISK

All history buffers are bounded:
- `vpn_optimizer.py` metrics_history: `deque(maxlen=5000)` -- ~400KB
- `vpn_optimizer.py` Q-table: LRU 10,000 entries -- ~800KB
- `vpn_optimizer.py` reward_history: `deque(maxlen=500)` -- ~4KB
- `marl_policy.py` reward_history: list, trimmed at 1000 -- ~8KB
- `marl_policy.py` Q-table: dict, **UNBOUNDED**
- `security_monitor.py` alerts: `deque(maxlen=5000)` -- ~2MB
- `security_monitor.py` request_tracker: dict of `deque(maxlen=500)` per user -- **GROWS WITH USERS**
- `policy_engine_worker.py` action_history: list, trimmed at 1000 -- ~80KB

**Finding DE-3:** `marl_policy.py` Q-table (line 120) is an unbounded `Dict`. Unlike `vpn_optimizer.py` which uses `LRUCache(maxsize=10000)`, the policy engine's Q-table can grow indefinitely. With the state hash producing `(10 * 10 * 10 * (latency/50) * 100 * 2)` combinations per server, this could reach hundreds of thousands of entries in a long-running server.

**Finding DE-4:** `security_monitor.py` `_request_tracker` (line 126) creates a new `deque(maxlen=500)` for every unique user_id that triggers `check_ai_agent_attack`. Over time, this accumulates entries for every user who has ever been checked, with no eviction of stale users.

---

## 8. Safety Guardrails Check

### 8.1 Can the Optimizer Make Dangerous Changes?

**Rating: LOW RISK**

The optimizer is advisory-only. Key safety properties:

1. **Kill switch:** The optimizer cannot disable any kill switch. The Dart client manages VPN state independently; the optimizer only suggests server IDs. There is no code path from the optimizer to any kill-switch toggle.

2. **DNS configuration:** The optimizer does not touch DNS settings. DNS leak protection (`dns_leak_protection.py`) is a separate, independent service. The optimizer's output is limited to `server_id`, `location`, latency/bandwidth estimates, and a confidence score.

3. **Protocol changes:** The optimizer cannot change the VPN protocol. Protocol selection is user-driven in `vpn_state.dart` line 122-128.

4. **Connection forcing:** The optimizer suggests servers; it never forces connections. The `select_optimal_server` method returns a dict, and the caller decides what to do with it.

5. **Policy actions scope:** The MARL policy engine can suggest REROUTE, THROTTLE, ROTATE_SERVER, and ALERT. In `policy_engine_worker.py`, REROUTE and ROTATE_SERVER update `session.assigned_node` in the database (lines 191-192, 199-200). THROTTLE only logs (line 197). ALERT creates an audit log entry. None of these directly modify the client's VPN tunnel.

### 8.2 Hard Limits on Optimizer Modifications

| What | Can Optimizer Change? | Hard Limit |
|------|-----------------------|------------|
| Kill switch | No | Not accessible |
| DNS servers | No | Separate service |
| VPN protocol | No | User-controlled |
| MTU | Client-side only | Fixed to 1280/1360/1420 |
| Keepalive | Client-side only | Fixed to 10/15/25 |
| Server assignment | Yes (DB field) | Server must exist in registry |
| Bandwidth allocation | Suggested only | No enforcement mechanism |

### 8.3 Panic / Safe Mode Fallback

**Finding SG-1:** There is no explicit "panic mode" or "safe mode" in the optimizer. If all ML components fail, the system degrades to rule-based scoring, which is safe. However, there is no mechanism to forcibly disable the ML pipeline at runtime (e.g., via feature flag or environment variable) without restarting the process.

The `v3.json` config includes a `success_criteria.non_blocking` field documenting that ML must never hard-block connectivity, but this is a documentation note, not an enforced constraint.

The MARL policy engine's safety constraints (line 167-208 in `marl_policy.py`) act as a de facto panic mode: if packet loss exceeds 10% or latency exceeds 500ms, safety overrides take precedence over any ML recommendation.

---

## 9. Findings Summary

### CRITICAL (0)

None.

### HIGH (1)

| ID | Component | Finding | Risk |
|----|-----------|---------|------|
| AP-3 | ml/data.py | Risk model training data has label leakage -- features are deterministic functions of labels. Model accuracy is meaningless on this dataset. | HIGH (methodological) |

### MEDIUM (5)

| ID | Component | Finding | Risk |
|----|-----------|---------|------|
| QOS-1 | xgb_qos.py | No input validation on QoSInput fields before XGBoost prediction | MEDIUM |
| RSK-1 | xgb_risk.py | No input validation on RiskInput fields before XGBoost prediction | MEDIUM |
| MRL-1 | marl_policy.py | evaluate_connection passes raw inputs to StateVector; int() on inf raises OverflowError | MEDIUM |
| DE-3 | marl_policy.py | Q-table dict is unbounded (no LRU eviction) | MEDIUM |
| DE-4 | security_monitor.py | _request_tracker grows unbounded per user | MEDIUM |

### LOW (4)

| ID | Component | Finding | Risk |
|----|-----------|---------|------|
| VOP-1 | vpn_optimizer.py | add_server does not validate initial_metrics | LOW |
| AP-2 | ml/data.py | load_telemetry_csv performs no validation on CSV values | LOW |
| FL-1 | marl_policy.py | Q-values not clamped (unlike vpn_optimizer.py) | LOW |
| SG-1 | All | No runtime kill switch for ML pipeline (requires restart) | LOW |

### INFORMATIONAL (2)

| ID | Component | Finding |
|----|-----------|---------|
| DE-1 | vpn_state.dart | 2-second timer is local-only, no network calls. Correct. |
| DE-2 | policy_engine_worker.py | 30-second eval loop opens DB session even with zero active sessions. Minor waste. |

---

## 10. Recommended Fixes (High-Confidence, Small Scope)

### Fix 1: Clamp Q-values in marl_policy.py (FL-1, DE-3)

Add Q-value clamping and consider LRU eviction for the policy engine Q-table, matching the pattern already used in `vpn_optimizer.py`.

Location: `services/marl_policy.py`, `_update_q_value` method (line 226-248).
Add after line 245: `new_q = max(-10.0, min(10.0, new_q))`
Add LRU eviction or maxsize check on `self.q_table`.

### Fix 2: Add input validation to QoSInput and RiskInput (QOS-1, RSK-1)

Add a `validate()` or `__post_init__` method to both dataclasses that clamps fields to expected ranges. This matches the pattern already used in `vpn_optimizer.py._validate_metric`.

### Fix 3: Guard against OverflowError in _hash_state (MRL-1)

Wrap `int()` conversions in `_hash_state` with try/except or pre-clamp float inputs.

### Fix 4: Add TTL eviction to security_monitor._request_tracker (DE-4)

Periodically prune entries older than the tracking window (default 60 seconds). A simple approach: on each `check_ai_agent_attack` call, remove entries for users whose most recent timestamp is older than 2x the window.

### Fix 5: Add input validation to add_server initial_metrics (VOP-1)

Route `initial_metrics` values through `_validate_metric` in the `add_server` method.

---

## 11. Architecture Assessment

### Strengths

1. **Defense in depth:** Three-layer fallback (XGBoost -> rule-based -> safe defaults) on all ML paths.
2. **Client-server separation:** Client-side predictor is pure arithmetic with no ML inference, no network calls during operation.
3. **Bounded memory:** Most buffers use deque/LRU with fixed maxlen.
4. **Safety overrides:** Hard constraints in the policy engine take precedence over ML recommendations.
5. **Thread safety:** SecurityMonitor uses proper locking.
6. **Lazy imports:** App functions without numpy/xgboost/sklearn.

### Weaknesses

1. **Synthetic training data:** Risk model is trained on features derived from labels (circular).
2. **Missing input validation:** API-facing functions accept unbounded inputs.
3. **No runtime ML kill switch:** Must restart to disable ML.
4. **Inconsistent Q-table management:** vpn_optimizer uses LRU+clamping; marl_policy uses unbounded dict.

### Overall Verdict

The ML pipeline is safe for production deployment in its current form. The optimizer is advisory-only and cannot make dangerous changes to VPN configuration, DNS, or kill switch state. Fallback behavior is robust. The primary concern is methodological (risk model training data leakage) rather than operational safety.

---

*End of review.*

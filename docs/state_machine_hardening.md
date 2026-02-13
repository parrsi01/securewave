# VPN State Machine Hardening

This document defines SecureWave's deterministic VPN connection state machine and the async/concurrency guardrails added in this hardening pass.

## State Set

- `disconnected`
- `connecting`
- `connected`
- `disconnecting`
- `error`

## Transition Table

| From | To | Trigger(s) | Guard |
|---|---|---|---|
| `disconnected` | `connecting` | `userConnectRequested`, `autoReconnectRequested` | only when `desiredOn=true` |
| `connecting` | `connected` | `connectOperationSucceeded` | only from active operation id |
| `connecting` | `disconnecting` | `userDisconnectRequested` | active connect operation is cancelled first |
| `connecting` | `disconnected` | `connectOperationCancelled` | stale/cancelled operation |
| `connecting` | `error` | `connectOperationFailed`, `timeout` | classified error with stable message |
| `connected` | `disconnecting` | `userDisconnectRequested` | serialized via reconcile loop |
| `connected` | `error` | connectivity kill-switch fault | only when kill-switch hooks present |
| `disconnecting` | `disconnected` | `disconnectOperationSucceeded` | cleanup + timer disposal |
| `disconnecting` | `error` | `disconnectOperationFailed`, `timeout` | classified error |
| `error` | `connecting` | retry/connect intent | reconnect path |

Invalid transitions are blocked and logged as `transition_blocked`.

## Triggers and Event Handling

Core trigger enum: `VpnTransitionTrigger` in `securewave_app/lib/core/state/vpn_state_machine.dart`.

Key triggers:
- User: `userConnectRequested`, `userDisconnectRequested`
- Auto flow: `autoReconnectRequested`, `initSync`
- Operation lifecycle: `connectOperationStarted`, `connectOperationSucceeded`, `connectOperationFailed`, `connectOperationCancelled`, `disconnectOperationStarted`, `disconnectOperationSucceeded`, `disconnectOperationFailed`
- Time bounds: `timeout`

## Async Guardrails

`VpnStateNotifier` now uses a serialized reconcile loop:
- Public APIs (`connect`, `disconnect`) only set user intent (`desiredOn`) and request reconcile.
- A single in-flight operation is allowed; conflicting intent cancels connect via an operation token.
- Connect/disconnect/profile-fetch are time-bounded via `VpnStateMachineConfig`.

Cancellation:
- Profile fetch uses Dio `CancelToken` to abort stale requests.
- Connect operations are cancelled when user intent flips to disconnect.

No unobserved futures:
- Fire-and-forget paths use `_safeFireAndForget` with structured error capture.

## Memory and Disposal Guardrails

- Data-rate simulation timer is started only on `connected` and cancelled on every exit from `connected`.
- Active operation token is cancelled on `dispose`.
- Transition history is bounded (`transitionHistoryLimit`) to avoid unbounded memory growth.
- Debug getters for tests:
  - `debugHasRateTimer`
  - `debugHasActiveOperation`
  - `debugTransitionHistory`

## UI Thread Safety

WireGuard config validation now supports isolate offload:
- For larger configs (>4KB), validation runs through `compute(...)`.
- Smaller configs stay inline for low overhead.

This prevents expensive parsing from blocking UI-critical event loops during connection startup.

## Logging Format

Structured logs are emitted at all state boundaries:
- intent updates
- operation start/end
- transition success
- transition blocked
- async task failures

Example:
```text
[VPN_SM] {"event":"transition","from":"connecting","to":"connected","trigger":"connectOperationSucceeded","operation_id":12}
```

Failure interpretation:
- `transition_blocked`: attempted illegal state edge (usually race input)
- `operation_cancelled`: stale connect superseded by newer intent
- `timeout`: operation exceeded configured bound

## Invariants

The suite enforces these invariants:
- Never remain in `connecting`/`disconnecting` indefinitely.
- At most one active operation token.
- Connect failures/timeouts clear `desiredOn` to prevent uncontrolled retry storms.
- Final state converges to user intent (`desiredOn`) after reconcile.
- Rapid connect/disconnect interleaving does not produce double-transition corruption.
- Timer/listener resources are disposed when disconnected or container disposed.

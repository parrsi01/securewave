# Mock VPN Architecture

## Overview

SecureWave Linux now supports two VPN execution modes behind a single adapter
boundary:

- `REAL MODE`: existing native VPN path through the production service bridge
- `MOCK MODE`: deterministic, no-system-call VPN simulation for tests and local
  development

Enable mock mode with:

```bash
--dart-define=SECUREWAVE_MOCK_VPN=true
```

## Components

- [`vpn_adapter.dart`](/home/sp/cyber-course/projects/securewave/securewave_app/lib/core/vpn/vpn_adapter.dart)
  defines the adapter contract used by the state machine.
- [`real_vpn_adapter.dart`](/home/sp/cyber-course/projects/securewave/securewave_app/lib/core/vpn/real_vpn_adapter.dart)
  delegates to the existing production `VpnService` path so real behavior stays
  unchanged.
- [`mock_vpn_adapter.dart`](/home/sp/cyber-course/projects/securewave/securewave_app/lib/core/vpn/mock_vpn_adapter.dart)
  simulates connect/disconnect/status without touching routes, interfaces, or
  native VPN tools.
- [`runtime_config.dart`](/home/sp/cyber-course/projects/securewave/securewave_app/lib/core/config/runtime_config.dart)
  exposes mock-mode and failure-simulation flags.
- [`vpn_factory.dart`](/home/sp/cyber-course/projects/securewave/securewave_app/lib/core/vpn/vpn_factory.dart)
  selects the adapter implementation.

## Mock Behavior

Default mock mode:

- connect latency: `300ms`
- result: success
- fake assigned IP: `10.8.0.100`
- disconnect: immediate
- native system calls: none

Optional simulation flags:

- `SECUREWAVE_MOCK_VPN_FORCE_FAILURE=true`
- `SECUREWAVE_MOCK_VPN_LATENCY_MS=2500`
- `SECUREWAVE_MOCK_VPN_UNSTABLE=true`

`LATENCY_MS` can exceed the state-machine timeout to exercise timeout handling
without a real tunnel.

## State-Machine Integration

The app still performs the same high-level flow:

1. resolve protocol
2. fetch profile
3. establish tunnel
4. verify and transition state

In mock mode:

- connect/disconnect go through `MockVpnAdapter`
- native health polling and traffic sampling are skipped
- runtime capability checks are forced ready locally
- backend profile fetch remains active, so API/profile contract coverage stays
  intact during integration tests

## Test Strategy

- Unit tests instantiate `MockVpnAdapter` directly.
- Linux integration scripts pass `SECUREWAVE_MOCK_VPN=true` by default.
- Real-mode coverage still lives in the existing service/native bridge tests.

# Contract characterization

These tests lock the public surface before structural refactoring. A failing
snapshot is not updated mechanically: the reviewer must decide whether the
change is compatible, versioned, documented, and covered by behavior tests.

Coverage is intentionally split across existing suites:

- `test_openapi_surface.py`: public auth, device, profile, usage, protocol, and
  downloads paths, methods, request-schema names, and key status codes.
- `tests/integration/test_auth_hardening.py`: active-account and token-version
  invalidation boundaries.
- `tests/integration/test_device_acl.py`: per-account device ownership.
- `tests/integration/test_usage_metering.py` and
  `test_postgres_usage_concurrency.py`: idempotency and concurrent sequence
  handling.
- `tests/unit/test_linux_helperd_behavior.py` and
  `test_linux_vpn_runner_contract.py`: helper contract and IPC allowlisting.
- `tests/unit/test_desktop_vpn_platform_truth.py`: fail-closed platform and
  protocol availability.
- `tests/unit/test_linux_vpn_runtime_verifier.py`: IKEv2 pref-220 loop rejection
  and cleanup evidence.
- `tests/unit/test_downloads_manifest.py`: manifest/API/download truth.

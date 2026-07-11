# Verified commands and results

## Automated tests

- Full Python suite:
  `/home/sp/cyber-course/projects/securewave/.venv/bin/python -m pytest -q`
  -> `326 passed`.
- Focused native/package/verifier suite -> `49 passed` before the final
  fail-closed capability adjustment; the full Python suite subsequently passed.
- Full Flutter suite: `flutter test --reporter compact` -> `26 passed`.
- Focused Flutter VPN suite after final capability adjustment:
  `flutter test test/mock_vpn_service_test.dart test/vpn_state_test.dart`
  -> `11 passed`.
- Flutter analyze after final capability adjustment -> no issues.

## Build/static/package checks

- `bash securewave_app/scripts/build_deb.sh` -> ARM64 package built locally;
  no publication.
- Linux Flutter release build -> success.
- Helper daemon `g++ -std=c++14 -Wall -Wextra -Werror ... -fsyntax-only` ->
  pass.
- Modified shell scripts `bash -n` -> pass.
- `bash scripts/verify_release_guards.sh` -> pass with socket-helper,
  no-connect-time-elevation, contract-10, and per-protocol source guards.
- Bandit high-severity scan of the verifier and behavior tests -> pass; one
  acknowledged `nosec B603` subprocess test-harness annotation warning.
- `git diff --check` -> pass after documentation newline cleanup.
- ShellCheck -> unavailable; not counted as a pass.
- Windows compile -> unavailable on Linux; not counted as a pass.
- macOS/Xcode compile -> unavailable on Linux; not counted as a pass.

## Behavior covered

- IPC malformed/duplicate/unknown fields and arbitrary operations.
- 64 KiB request limit and socket timeouts.
- helper contract mismatch and service/socket unavailable states.
- path ownership, symlink, filename, and runtime directory restrictions.
- WireGuard arbitrary hook rejection and exact kill-switch hook allowlist.
- OpenVPN script/plugin/include/file-write/external-credential and inline
  plaintext-credential rejection.
- OpenVPN root process plus exact config identity.
- WireGuard/OpenVPN/IKEv2 availability and fail-closed evidence gates.
- IKEv2 XFRM/pref-220 semantics.
- traffic counter delta, reset, disconnect, and concurrent poll behavior.
- package payload, dependencies, narrow allowlist, removal cleanup, and portable
  UI-only truth.

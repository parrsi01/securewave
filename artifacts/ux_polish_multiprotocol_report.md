# UX Polish Multiprotocol Report

Date (UTC): 2026-02-22
Branch: `release/multiprotocol-live-only`

## Scope

Polished multi-protocol VPN UX messaging and platform communication so users can clearly understand:
- which protocols are actually selectable,
- what protocol is in use,
- what the app is doing during slow connects,
- what platform helpers/components are required,
- and what actions to take on errors.

## What Changed

### 1) Protocol Selector (real support only + clearer platform differences)
File: `securewave_app/lib/screens/settings/settings_screen.dart`

- Kept existing live-only gating behavior (selector only renders protocols marked `available` by `ProtocolCapabilityMatrix`).
- Added protocol-specific helper subtitles under each selectable protocol tile.
- Added platform/runtime-specific helper text (examples: OpenVPN local runtime, Linux IKEv2 OS helper, Windows built-in VPN path).
- Replaced `GestureDetector` tile tap handling with `Material` + `InkWell` for better focus/keyboard behavior.
- Added semantics labels/hints and selected-state announcements for screen readers.

### 2) Status / Connection UX (protocol in use + slow connect progress)
File: `securewave_app/lib/screens/home/widgets/status_display.dart`

- Added visible protocol pills showing:
  - selected/effective protocol mapping (`Automatic -> OpenVPN`, etc.)
  - platform helper/runtime hint (`Requires OS helper`, `Uses built-in Windows VPN`, etc.)
- Surfaced `protocolMessage` in a non-error informational notice when present.
- Added connection-progress feedback panel during `Connecting`:
  - staged status text (preparing profile / starting runtime / waiting for OS helper)
  - progress bar (non-final, capped) + elapsed seconds
  - actionable plain-language detail text
- Added `Semantics` live-region labeling for status/error/progress content.

### 3) Connection Button Accessibility (ring)
File: `securewave_app/lib/screens/home/widgets/connection_ring.dart`

- Improved connection ring semantics to announce:
  - current VPN status
  - active/selected protocol
  - next action hint (connect/disconnect) or busy state

### 4) Platform Requirements Notice (clearer helper requirements)
File: `securewave_app/lib/ui/widgets/platform_notice.dart`

- Reworked platform notice into a titled bullet-list layout for readability.
- Added screen-reader-friendly `Semantics` container + live-region labeling.
- Updated Linux/Windows copy to explicitly communicate helper/runtime requirements (including “Requires OS helper” wording for IKEv2/OpenVPN on Linux where appropriate).

## Validation

### `flutter analyze`
- Completed successfully with pre-existing informational lint findings only (no new compile errors from this UX patch).

### `flutter test`
- Passed (`All tests passed`)

## Notes / Remaining UX Opportunities

- `protocolMessage` is now rendered, but current `ProtocolSelector.resolve()` does not yet emit warnings in most paths; future backend/runtime heuristics can populate it for richer guidance.
- A dedicated widget test for the new status progress panel and protocol pills would improve regression coverage.

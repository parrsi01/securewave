# SecureWave Flutter Dashboard And Selection Overhaul

Date: 2026-05-09

## Executive Summary

This pass rebuilt the core operational Flutter UI for SecureWave: the VPN home/dashboard, connection-state control surface, current server visibility, server selection, and protocol selection presentation. The implementation uses the prior design-system foundation to create a premium dark high-tech control surface while preserving the existing VPN state machine, provider contracts, backend/catalog behavior, and release truth.

No protocol behavior was changed. WireGuard remains the only public selectable protocol. OpenVPN remains visibly restricted and not public-selectable in this UI. IKEv2 remains not public v1 release-visible. No fake connected state or broadened readiness claim was introduced.

## Files Changed

| File | Change |
| --- | --- |
| `securewave_app/lib/features/vpn/vpn_page.dart` | Rebuilt the home/dashboard connection control surface, connection states, current server visibility, protocol visibility, metrics, notices, and diagnostics entry. |
| `securewave_app/lib/features/servers/servers_page.dart` | Rebuilt server selection into responsive premium cards with selected/favorite/latency/adaptive score states. |
| `securewave_app/lib/features/vpn/protocol_selection_panel.dart` | Added reusable protocol selection panel with truthful public-release availability rules. |
| `securewave_app/lib/features/settings/settings_page.dart` | Replaced the old protocol radio list with the shared protocol selection panel only. |
| `artifacts/flutter_ui_dashboard_and_selection_overhaul.md` | Added this implementation artifact. |

This branch also still contains the prior UI foundation and auth overhaul artifacts from earlier prompts.

## Surfaces Rebuilt

| Surface | Result |
| --- | --- |
| Dashboard disconnected | Rebuilt as a dark SecureWave control surface with clear disconnected status, non-fake ring progress, selected server/protocol badges, and truthful connect availability. |
| Dashboard connecting | Uses busy state, amber state color, indeterminate ring progress, loading center action, and haptic flow already wired through existing state transitions. |
| Dashboard connected | Uses success state only when `VpnStatus.connected` is real, with live data-rate metrics and stability score sourced from existing state. |
| Dashboard disconnecting | Uses amber transitional state, clean closing copy, and existing disconnect action behavior. |
| Dashboard error | Uses backend-aware warning/danger status and existing error message semantics. |
| Current server visibility | Shows auto-select or the saved/selected server. A small UI-binding correction prevents an unknown saved server id from being mislabeled as the first catalog server. |
| Server selection | Rebuilt into responsive selection cards with auto-select, manual regions, favorites, latency, selected state, and MarLXGB adaptive score display. |
| Protocol selection | Added reusable panel used from dashboard and settings. WireGuard is selectable. OpenVPN and IKEv2 are visible but blocked with truthful release-status labels. |

## State And Behavior Preserved

| Behavior | Preservation |
| --- | --- |
| Connect action | Still calls `vpnStateProvider.notifier.connect()` only through the existing button flow. |
| Disconnect action | Still calls `vpnStateProvider.notifier.disconnect()` only through the existing button flow. |
| Busy gating | Existing `vpnState.isBusy` and native availability/mock fallback checks still gate the action. |
| Server selection | Still calls `selectServer(server.id)` or `selectServer(null)` for auto-select. |
| Favorite server behavior | Still uses `favoriteServersProvider.notifier.toggle(server.id)`. |
| Protocol selection | Still calls `selectProtocol(value)` only for enabled WireGuard selection. Disabled cards do not call the notifier. |
| Diagnostics | Still opens `ConnectionDiagnosticsSheet.show(context)`. |
| Runtime/platform notices | Existing platform truth was preserved and restyled. |

## Release Truth Preserved

| Protocol/runtime item | UI rule |
| --- | --- |
| WireGuard | Primary and public-selectable release-candidate protocol. |
| OpenVPN | Visible as restricted; not public-selectable in this UI. |
| IKEv2/IPSec | Visible as not public v1; not selectable. |
| Linux desktop public v1 | Preserved in platform notices and behavior. |
| Unsupported native runtime states | Shown as setup/unavailable/demo mode based on existing native availability and mock config. |
| Connected visuals | Only shown for `VpnStatus.connected`. Connecting/disconnecting/error/disconnected receive distinct colors and copy. |

## Layout Rules

| Device class | Behavior |
| --- | --- |
| Phone / compact Android | Single-column dashboard; connection surface first, server/protocol cards below; server selection uses one card per row. |
| Tablet / iPad | Dashboard becomes two-column once width allows; server grid uses two cards per row. |
| Laptop / desktop | Dashboard uses a wide control panel plus side selection column; server selection uses spacious two-column cards. |

## Motion And State Treatment

| Interaction | Treatment |
| --- | --- |
| Connect state ring | Animated ring color/progress responds to disconnected, connecting, connected, disconnecting, and error states. |
| Busy state | Indeterminate ring and loading center action use real `vpnState.isBusy`. |
| Server selection | Selected cards animate border/glow and preserve favorite controls. |
| Protocol selection | Selected WireGuard card animates border/glow; blocked protocols remain visible with lock treatment. |
| State transitions | Existing route/page transitions and design-system durations are reused. |

## Protected Boundaries

No changes were made to:

| Boundary | Status |
| --- | --- |
| `securewave_app/lib/core/state/vpn_state.dart` | Untouched. |
| `securewave_app/lib/core/services/vpn_service.dart` | Untouched. |
| `securewave_app/lib/services/api_client.dart` | Untouched. |
| Backend/catalog APIs | Untouched. |
| Linux helper/runtime/native platform behavior | Untouched. |
| Routing semantics | Untouched. |
| `securewave_app/pubspec.yaml`, `securewave_app/pubspec.lock` | Untouched. |
| Packaging/release files | Untouched. |

## Validation Snapshot

| Command | Result |
| --- | --- |
| `flutter analyze` from `securewave_app/` | Passed after implementation. |
| `flutter test` from `securewave_app/` | Passed after implementation. |
| `git diff --check` | Passed: no whitespace errors. |

## Remaining Visual Debt

| Area | Reason |
| --- | --- |
| Rendered multi-device QA | This pass used static Flutter validation, but did not capture screenshots across phone/tablet/desktop viewports. |
| Wider settings page | Only the protocol selection surface in settings was rebuilt; other settings sections remain older surfaces. |
| Shell navigation polish | Operational dashboard content was rebuilt, but app shell rail/drawer polish remains a later UI pass. |

## Strict Change Log

| Category | Detail |
| --- | --- |
| What changed | Dashboard control surface, connection ring/state presentation, current server card, server selection cards/grid, reusable protocol selection panel, settings protocol section presentation, artifact. |
| What was reused | Existing VPN state provider, connect/disconnect methods, server provider, favorite server provider, MarLXGB scoring, diagnostics sheet, platform notices, haptic hooks, design-system foundation. |
| What was intentionally left untouched | VPN state machine, protocol availability logic, backend/catalog truth, routing semantics, Linux helper/native runtime, dependencies/lockfiles, packaging/release files. |
| Risks introduced | Visual-only layout shift. Device screenshot QA remains open, and non-protocol settings still carry older visual treatment. |

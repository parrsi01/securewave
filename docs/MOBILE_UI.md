# SecureWave shared Flutter UI

The shared Flutter interface is an operational VPN control surface. It uses the
existing Riverpod session, catalog, plan, and VPN state providers; it does not
invent connection, traffic, location, or protocol data.

## Design rules

- Spacing uses a 4/8/12/16/24/32 scale, with 8–10 px component radii.
- Interactive controls have at least a 44 px height; icon buttons use 48 px.
- Blue identifies primary actions, green is reserved for a proven connected
  state, amber means transitional or limited operation, and red means an error.
- Narrow layouts stack primary and secondary connection actions before they can
  overflow. Content is capped at 1160 px on desktop.
- Connection state is a semantic live region. Selectable server and protocol
  rows expose selected, enabled, label, and value semantics.

## Runtime truth

- Protocol choices use `VpnService.canConnectProtocol` and
  `protocolUnavailableReason`.
- A region is disabled when its catalog metadata does not list the selected
  protocol. An empty protocol list retains the existing backward-compatible
  meaning that the legacy catalog did not declare restrictions.
- The platform-support panel reports only the native bridge state observed by
  the current build. Download guidance sends users to the account portal and
  makes no package-availability claim.
- Session traffic remains described as account-metered because live bridge
  rates are not exposed by this UI.

## Verification

Run `flutter analyze`, `flutter test`, and the safe platform builds from
`securewave_app/`. Golden tests cover a 390x844 connected mobile state and a
1280x800 disconnected desktop state. Their committed evidence is under
`artifacts/mobile-ui-refactor/`.

# Mobile UI refactor evidence

- `mobile-connected-390x844.png`: connected shared Flutter UI at a narrow mobile
  viewport, rendered from a deterministic test provider.
- `desktop-disconnected-1280x800.png`: disconnected desktop layout with the
  wide navigation and paired session/usage panels.

The images are regression-tested by `test/mobile_ui_visual_test.dart`. The test
data is explicitly synthetic test-fixture data and is not presented by a
production build as live VPN or account data.

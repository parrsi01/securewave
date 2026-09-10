# VPN app design

The VPN app follows the public website's black and blue visual identity in
[WEBSITE_DESIGN_LOCK.md](WEBSITE_DESIGN_LOCK.md). This applies to login,
registration, Home/connection controls, Account, Diagnostics, and error states.

Use near-black `#03060d`, navy `#060c18` / `#080f20`, cyan `#00b4ff`,
blue `#0066cc`, and light text `#d0e8ff`. Secondary text is lighter than the
website's small muted labels to maintain readable contrast in desktop controls.
Use Space Grotesk for general text and JetBrains Mono for technical labels and
connection statistics. Both fonts are bundled locally with their OFL licenses;
font loading requires no network request. Font sources are the Google Fonts
repository's `ofl/spacegrotesk` and `ofl/jetbrainsmono` directories.

Keep the hexagon/shield/wave mark, compact bordered surfaces, cyan actions,
and clear selected navigation. Warning and error colors convey status and
must retain readable foreground contrast. At narrow widths use bottom
navigation and scrollable forms. Enlarged text must not hide connection errors.

Visual changes preserve normal account verification, authentication, native
WireGuard state, and cleanup. Fixture screenshots and widget tests establish
presentation behavior only. Real beta acceptance still requires the installed
package, an authorized verified account, and actual tunnel/egress/cleanup proof.

## Checks and review images

From `securewave_app`, run `flutter analyze` and `flutter test`.
To export review screenshots from deterministic UI fixtures, run:

```sh
flutter test test/fresh_ui_state_test.dart --plain-name black-blue \
  --dart-define=SW_UI_CAPTURE_DIR=/tmp/securewave-ui-review
```

The images show test data, not a live account or active VPN. Keep generated
captures outside the source tree.

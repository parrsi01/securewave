# Rescue Diff Audit (2026-02-26)

## Phase 0 Snapshot

### git status
```
## rescue/rollback_and_rebuild_20260226
 M artifacts/watchdog/watchdog_events.jsonl
?? docs/guides/FLUTTER_APP_LINUX_LIVE_VALIDATION_SNAPSHOT_2026-02-26.md
?? docs/guides/FLUTTER_APP_LIVE_COMPONENT_DEBUG_REPORT_2026-02-26.md
?? docs/guides/FLUTTER_APP_VPN_NETWORK_ROUTING_DEBUG_REPORT_2026-02-26.md
?? docs/guides/RESCUE_DIFF_AUDIT_2026-02-26.md
?? docs/guides/RUNTIME_TUNNEL_BASELINE_2026-02-26.md
?? docs/guides/SECUREWAVE_FULL_RUNTIME_VALIDATION_REPORT_2026-02-26.md
?? docs/guides/SECUREWAVE_VPN_RUNTIME_FIX_REPORT_2026-02-26.md
?? docs/guides/runtime_probe/
?? tools/
```

### git log --oneline --decorate -n 20
```
7c02065 (HEAD -> rescue/rollback_and_rebuild_20260226, tag: rescue_pre_cleanup_20260226_231103, origin/release/multiprotocol-live-only, release/multiprotocol-live-only) fix: CI green — pubspec .env asset, workflow YAML, secret scanner false positives
b7b5254 feat: OpenVPN/IKEv2 fix, traffic stats gauge, multi-location + premium tiers
c7fc521 docs: add VPN/Wi-Fi disconnect connectivity debug report
fda7906 fix: restore multiprotocol vpn visibility and dynamic region flow
d92b458 fix: resolve WiFi toggle bug, clean flutter analyze, add macOS network entitlement
98ca2ff feat: wire live Hetzner backend, fix login hang, harden VPN health monitor
8841694 release: rebuild linux package and republish manifest
ab70b33 hardening: tighten boot, session, and protocol flows
38142e1 fix: unblock boot startup and refine branding
1eeda96 perf: optimize multiprotocol client runtime overhead
8ce6115 feat: polish multiprotocol connection ux messaging
97c3925 ci: add multiprotocol release guardrail workflow
7f14072 test: refresh multiprotocol live validation artifacts
6aec73a docs: refresh phase4 release validation report
f4c6783 docs: refresh phase3 desktop validation report
813af63 docs: refresh phase2 server validation report
d11bdd0 chore: remove remaining demo/mock workflow flags and labels
c262592 feat: add multi-protocol live validation suite and CI
2b71905 feat: add manifest-driven release pipeline and website downloads
00a1022 Implement desktop OpenVPN/IKEv2 protocol connectors and gating
```

## Diff Map vs d92b458

### git diff --stat d92b458..HEAD
```
 .github/workflows/flutter-release.yml              |   8 +-
 .pre-commit-config.yaml                            |   7 +
 CLAUDE.md                                          | 141 ++++
 ...ONNECTIVITY_VPN_WIFI_DISCONNECT_DEBUG_REPORT.md |  82 ++
 infrastructure/hetzner/audit_vpn_fleet.py          | 710 ++++++++++++++++
 infrastructure/hetzner/sync_vpn_servers.py         | 109 ++-
 routes/vpn.py                                      | 573 ++++++++++++-
 scripts/ci_multiprotocol_safety_check.sh           |   4 +-
 scripts/repair_vpn_registry.py                     | 246 ++++++
 .../lib/core/bootstrap/boot_controller.dart        |  10 +
 securewave_app/lib/core/config/app_config.dart     |  77 +-
 .../lib/core/constants/app_constants.dart          |   6 +-
 securewave_app/lib/core/models/server_region.dart  | 151 +++-
 .../lib/core/services/protocol_selector.dart       |  60 +-
 .../lib/core/services/secure_storage.dart          |   2 +
 securewave_app/lib/core/services/vpn_service.dart  | 295 ++++++-
 securewave_app/lib/core/state/app_state.dart       |   5 +
 .../lib/core/state/preferences_state.dart          | 114 ++-
 securewave_app/lib/core/state/vpn_state.dart       | 162 +++-
 securewave_app/lib/core/utils/api_error.dart       |  12 +-
 .../lib/core/vpn/protocol_capabilities.dart        |  59 +-
 .../lib/features/auth/auth_controller.dart         |  30 +-
 securewave_app/lib/features/auth/login_page.dart   |  27 +-
 .../lib/screens/home/widgets/status_display.dart   |   6 +-
 .../lib/screens/locations/locations_screen.dart    | 203 +++--
 .../lib/screens/locations/widgets/server_tile.dart | 294 ++++---
 .../lib/screens/settings/settings_screen.dart      | 853 ++++++++++++++++----
 securewave_app/lib/services/api_client.dart        |  89 +-
 securewave_app/linux/install-vpn-policy.sh         |  40 +
 securewave_app/linux/runner/my_application.cc      | 896 +++++++++++++++++++--
 securewave_app/linux/securewave-vpn-policy.rules   |  19 +
 securewave_app/pubspec.yaml                        |   1 -
 .../channel_vpn_service_cache_test.dart            |  53 ++
 .../test/protocol_capability_matrix_test.dart      |  25 +
 securewave_app/test/protocol_selector_test.dart    |  31 +-
 .../state_machine/auto_connect_listener_test.dart  |  79 ++
 .../state_machine/state_machine_test_harness.dart  |  53 +-
 securewave_app/test/vpn_state_test.dart            | 118 +++
 .../test/widgets/connection_button_test.dart       |  32 +
 services/vpn_server_service.py                     |  56 +-
 start_site.sh                                      |  20 +
 tests/integration/test_vpn_profile.py              |  24 +-
 tests/integration/test_vpn_protocols_endpoint.py   |  20 +
 43 files changed, 5248 insertions(+), 554 deletions(-)
```

### git diff --name-only d92b458..HEAD
```
.github/workflows/flutter-release.yml
.pre-commit-config.yaml
CLAUDE.md
docs/guides/CONNECTIVITY_VPN_WIFI_DISCONNECT_DEBUG_REPORT.md
infrastructure/hetzner/audit_vpn_fleet.py
infrastructure/hetzner/sync_vpn_servers.py
routes/vpn.py
scripts/ci_multiprotocol_safety_check.sh
scripts/repair_vpn_registry.py
securewave_app/lib/core/bootstrap/boot_controller.dart
securewave_app/lib/core/config/app_config.dart
securewave_app/lib/core/constants/app_constants.dart
securewave_app/lib/core/models/server_region.dart
securewave_app/lib/core/services/protocol_selector.dart
securewave_app/lib/core/services/secure_storage.dart
securewave_app/lib/core/services/vpn_service.dart
securewave_app/lib/core/state/app_state.dart
securewave_app/lib/core/state/preferences_state.dart
securewave_app/lib/core/state/vpn_state.dart
securewave_app/lib/core/utils/api_error.dart
securewave_app/lib/core/vpn/protocol_capabilities.dart
securewave_app/lib/features/auth/auth_controller.dart
securewave_app/lib/features/auth/login_page.dart
securewave_app/lib/screens/home/widgets/status_display.dart
securewave_app/lib/screens/locations/locations_screen.dart
securewave_app/lib/screens/locations/widgets/server_tile.dart
securewave_app/lib/screens/settings/settings_screen.dart
securewave_app/lib/services/api_client.dart
securewave_app/linux/install-vpn-policy.sh
securewave_app/linux/runner/my_application.cc
securewave_app/linux/securewave-vpn-policy.rules
securewave_app/pubspec.yaml
securewave_app/test/performance/channel_vpn_service_cache_test.dart
securewave_app/test/protocol_capability_matrix_test.dart
securewave_app/test/protocol_selector_test.dart
securewave_app/test/state_machine/auto_connect_listener_test.dart
securewave_app/test/state_machine/state_machine_test_harness.dart
securewave_app/test/vpn_state_test.dart
securewave_app/test/widgets/connection_button_test.dart
services/vpn_server_service.py
start_site.sh
tests/integration/test_vpn_profile.py
tests/integration/test_vpn_protocols_endpoint.py
```

## Patch Extract: securewave_app/linux/runner/my_application.cc

```diff
diff --git a/securewave_app/linux/runner/my_application.cc b/securewave_app/linux/runner/my_application.cc
index 1021672..b1a9fc4 100644
--- a/securewave_app/linux/runner/my_application.cc
+++ b/securewave_app/linux/runner/my_application.cc
@@ -23,12 +23,17 @@ static inline gboolean g_spawn_check_wait_status(gint wait_status,
 
 namespace {
 const char* kChannelName = "securewave/vpn";
-const char* kWireGuardConfigFileName = "securewave-wireguard.conf";
+// wg-quick derives the interface name from the config basename and enforces
+// Linux interface-name length limits (15 chars max). Keep this short.
+const char* kWireGuardConfigFileName = "sw-wg.conf";
 const char* kOpenVpnConfigFileName = "securewave-openvpn.ovpn";
 const char* kOpenVpnAuthFileName = "securewave-openvpn.auth";
 const char* kOpenVpnPidFileName = "securewave-openvpn.pid";
 const char* kIkev2ConnectionName = "SecureWave-IKEv2";
 const guint kWgQuickTimeoutMs = 30000;
+const char* kPrivilegeHelperPath = "/usr/local/libexec/securewave-wg-quick";
+const char* kPrivilegeRulePath =
+    "/etc/polkit-1/rules.d/80-securewave-wireguard.rules";
 
 typedef struct {
   FlMethodChannel* channel;
@@ -40,6 +45,8 @@ typedef struct {
   gboolean last_connected;
 } VpnChannelState;
 
+static const gchar* elevation_hint_message();
+
 static void vpn_channel_state_free(VpnChannelState* state) {
   if (!state) {
     return;
@@ -111,6 +118,14 @@ static gboolean pkexec_available() {
   return pkexec != nullptr;
 }
 
+static gboolean privilege_helper_installed() {
+  return g_file_test(kPrivilegeHelperPath, G_FILE_TEST_IS_EXECUTABLE);
+}
+
+static gboolean privilege_rule_installed() {
+  return g_file_test(kPrivilegeRulePath, G_FILE_TEST_EXISTS);
+}
+
 static gboolean has_desktop_auth_session() {
   const gchar* display = g_getenv("DISPLAY");
   if (display && *display != '\0') {
@@ -127,6 +142,11 @@ static gboolean elevation_available() {
   if (geteuid() == 0) {
     return TRUE;
   }
+  // When the scoped SecureWave helper + polkit rule are installed, pkexec can
+  // authorize the helper non-interactively for the active local user.
+  if (pkexec_available() && privilege_helper_installed() && privilege_rule_installed()) {
+    return TRUE;
+  }
   // GUI apps can't reliably prompt for sudo passwords; prefer pkexec + a
   // desktop auth session so users get a permission dialog instead of a silent
   // shell failure path.
@@ -134,14 +154,151 @@ static gboolean elevation_available() {
 }
 
 static gboolean native_vpn_available() {
-  const gboolean can_elevate = elevation_available();
-  if (!can_elevate) {
-    return FALSE;
-  }
+  // Availability means a supported runtime is installed. Elevation is checked
+  // separately during connect/disconnect so the UI/autoconnect path can surface
+  // a permission-specific error instead of "not configured".
   return wg_quick_available() || openvpn_available() ||
          (nmcli_available() && ipsec_available());
 }
 
+static gboolean spawn_sync_capture(gchar** argv,
+                                   gchar** out_stdout,
+                                   gchar** out_stderr,
+                                   gint* out_status,
+                                   GError** error) {
+  return g_spawn_sync(nullptr,
+                      argv,
+                      nullptr,
+                      G_SPAWN_SEARCH_PATH,
+                      nullptr,
+                      nullptr,
+                      out_stdout,
+                      out_stderr,
+                      out_status,
+                      error);
+}
+
+static gboolean install_privilege_automation(gchar** out_message) {
+  if (out_message) *out_message = nullptr;
+  if (geteuid() != 0 && (!pkexec_available() || !has_desktop_auth_session())) {
+    if (out_message) {
+      *out_message = g_strdup(
+          "Privilege setup requires pkexec and a desktop authentication session.");
+    }
+    return FALSE;
+  }
+
+  const gchar* current_user = g_get_user_name();
+  if (!current_user || *current_user == '\0' || strchr(current_user, '\'') != nullptr) {
+    if (out_message) {
+      *out_message = g_strdup("Unable to determine a safe local username for polkit rule installation.");
+    }
+    return FALSE;
+  }
+
+  g_autofree gchar* script = g_strdup_printf(
+      "set -eu\n"
+      "install -d -m 0755 /usr/local/libexec\n"
+      "cat > /usr/local/libexec/securewave-wg-quick <<'EOS'\n"
+      "#!/bin/sh\n"
+      "set -eu\n"
+      "if [ \"$#\" -ne 2 ]; then echo 'invalid args' >&2; exit 2; fi\n"
+      "action=\"$1\"\n"
+      "cfg=\"$2\"\n"
+      "case \"$action\" in up|down) ;; *) echo 'invalid action' >&2; exit 2;; esac\n"
+      "case \"$cfg\" in\n"
+      "  /home/*/.config/securewave/sw-wg.conf|/root/.config/securewave/sw-wg.conf|"
+      "/home/*/.config/securewave/securewave-wireguard.conf|/root/.config/securewave/securewave-wireguard.conf) ;;\n"
+      "  *) echo 'config path not allowed' >&2; exit 2;;\n"
+      "esac\n"
+      "exec /usr/bin/env wg-quick \"$action\" \"$cfg\"\n"
+      "EOS\n"
+      "chmod 0755 /usr/local/libexec/securewave-wg-quick\n"
+      "install -d -m 0755 /etc/polkit-1/rules.d\n"
+      "cat > /etc/polkit-1/rules.d/80-securewave-wireguard.rules <<'EOS'\n"
+      "polkit.addRule(function(action, subject) {\n"
+      "  if (action.id != 'org.freedesktop.policykit.exec') return;\n"
+      "  var program = action.lookup('program');\n"
+      "  if (program != '/usr/local/libexec/securewave-wg-quick') return;\n"
+      "  if (subject.user == '%s' && subject.local && subject.active) {\n"
+      "    return polkit.Result.YES;\n"
+      "  }\n"
+      "});\n"
+      "EOS\n",
+      current_user);
+
+  g_autoptr(GError) error = nullptr;
+  gchar* stdout_text = nullptr;
+  gchar* stderr_text = nullptr;
+  gint status = 0;
+  gboolean ok = FALSE;
+  if (geteuid() == 0) {
+    gchar* argv[] = {const_cast<gchar*>("/bin/sh"), const_cast<gchar*>("-c"),
+                     script, nullptr};
+    ok = spawn_sync_capture(argv, &stdout_text, &stderr_text, &status, &error);
+  } else {
+    gchar* argv[] = {const_cast<gchar*>("pkexec"), const_cast<gchar*>("/bin/sh"),
+                     const_cast<gchar*>("-c"), script, nullptr};
+    ok = spawn_sync_capture(argv, &stdout_text, &stderr_text, &status, &error);
+  }
+  g_autofree gchar* out_free = stdout_text;
+  g_autofree gchar* err_free = stderr_text;
+  if (!ok) {
+    if (out_message) *out_message = g_strdup(error ? error->message : "Setup failed");
+    return FALSE;
+  }
+  if (!g_spawn_check_wait_status(status, &error)) {
+    if (out_message) {
+      *out_message = g_strdup((stderr_text && *stderr_text) ? stderr_text
+                                                            : (error ? error->message : "Setup failed"));
+    }
+    return FALSE;
+  }
+  if (out_message) *out_message = g_strdup("Linux privilege automation enabled.");
+  return TRUE;
+}
+
+static gboolean remove_privilege_automation(gchar** out_message) {
+  if (out_message) *out_message = nullptr;
+  const char* script =
+      "set -eu\n"
+      "rm -f /etc/polkit-1/rules.d/80-securewave-wireguard.rules\n"
+      "rm -f /usr/local/libexec/securewave-wg-quick\n";
+  g_autoptr(GError) error = nullptr;
+  gchar* stdout_text = nullptr;
+  gchar* stderr_text = nullptr;
+  gint status = 0;
+  gboolean ok = FALSE;
+  if (geteuid() == 0) {
+    gchar* argv[] = {const_cast<gchar*>("/bin/sh"), const_cast<gchar*>("-c"),
+                     const_cast<gchar*>(script), nullptr};
+    ok = spawn_sync_capture(argv, &stdout_text, &stderr_text, &status, &error);
+  } else {
+    if (!pkexec_available() || !has_desktop_auth_session()) {
+      if (out_message) *out_message = g_strdup(elevation_hint_message());
+      return FALSE;
+    }
+    gchar* argv[] = {const_cast<gchar*>("pkexec"), const_cast<gchar*>("/bin/sh"),
+                     const_cast<gchar*>("-c"), const_cast<gchar*>(script), nullptr};
+    ok = spawn_sync_capture(argv, &stdout_text, &stderr_text, &status, &error);
+  }
+  g_autofree gchar* out_free = stdout_text;
+  g_autofree gchar* err_free = stderr_text;
+  if (!ok) {
+    if (out_message) *out_message = g_strdup(error ? error->message : "Disable failed");
+    return FALSE;
+  }
+  if (!g_spawn_check_wait_status(status, &error)) {
+    if (out_message) {
+      *out_message = g_strdup((stderr_text && *stderr_text) ? stderr_text
+                                                            : (error ? error->message : "Disable failed"));
+    }
+    return FALSE;
+  }
+  if (out_message) *out_message = g_strdup("Linux privilege automation disabled.");
+  return TRUE;
+}
+
 static const gchar* wireguard_install_hint_message() {
   return "Install wireguard-tools (e.g. sudo apt-get install wireguard-tools) and retry.";
 }
@@ -216,6 +373,34 @@ static gchar* last_non_empty_line(const gchar* text) {
   return nullptr;
 }
 
+static gchar* normalize_linux_wireguard_config(const gchar* config) {
```

## Patch Extract: securewave_app/lib/screens/settings/settings_screen.dart

```diff
diff --git a/securewave_app/lib/screens/settings/settings_screen.dart b/securewave_app/lib/screens/settings/settings_screen.dart
index b04813f..677f0d0 100644
--- a/securewave_app/lib/screens/settings/settings_screen.dart
+++ b/securewave_app/lib/screens/settings/settings_screen.dart
@@ -4,7 +4,9 @@ import 'package:flutter/material.dart';
 import 'package:flutter/services.dart';
 import 'package:flutter_riverpod/flutter_riverpod.dart';
 import 'package:go_router/go_router.dart';
+import 'package:platform_info/platform_info.dart';
 
+import '../../core/config/app_config.dart';
 import '../../core/models/vpn_protocol.dart';
 import '../../core/models/vpn_protocol_catalog.dart';
 import '../../core/models/vpn_status.dart';
@@ -13,8 +15,10 @@ import '../../core/state/app_state.dart';
 import '../../core/state/preferences_state.dart';
 import '../../core/services/vpn_service.dart';
 import '../../core/state/vpn_state.dart';
+import '../../core/utils/api_error.dart';
 import '../../core/vpn/protocol_capabilities.dart';
 import '../../features/onboarding/feedback_sheet.dart';
+import '../../services/api_client.dart';
 import '../../ui/design/app_animations.dart';
 import '../../ui/design/app_colors.dart';
 import '../../ui/design/app_spacing.dart';
@@ -34,6 +38,7 @@ class SettingsScreen extends ConsumerStatefulWidget {
 class _SettingsScreenState extends ConsumerState<SettingsScreen> {
   bool _diagExpanded = false;
   List<_DiagResult>? _diagResults;
+  bool _diagRunning = false;
   bool _reconnecting = false;
 
   @override
@@ -46,8 +51,15 @@ class _SettingsScreenState extends ConsumerState<SettingsScreen> {
     final isDark = Theme.of(context).brightness == Brightness.dark;
     final selectedProtocol =
         ref.watch(vpnStateProvider.select((s) => s.protocol));
+    final vpnStatus = ref.watch(vpnStateProvider.select((s) => s.status));
+    final vpnBusy = ref.watch(vpnStateProvider.select((s) => s.isBusy));
     final caps = ref.watch(vpnCapabilitiesProvider);
+    final privilegeAutomation = ref.watch(vpnPrivilegeAutomationStatusProvider);
     final catalog = ref.watch(vpnProtocolCatalogProvider);
+    final settingsControlsEnabled = !_reconnecting &&
+        !vpnBusy &&
+        vpnStatus != VpnStatus.connecting &&
+        vpnStatus != VpnStatus.disconnecting;
 
     return Center(
       child: ConstrainedBox(
@@ -66,9 +78,24 @@ class _SettingsScreenState extends ConsumerState<SettingsScreen> {
                   ref.watch(preferencesProvider.select((p) => p.autoConnect)),
               onChanged: (v) =>
                   ref.read(preferencesProvider.notifier).setAutoConnect(v),
+              enabled: settingsControlsEnabled,
               isDark: isDark,
             ),
             const SizedBox(height: AppSpacing.space2),
+            _PrivilegeAutomationCard(
+              isDark: isDark,
+              enabled: settingsControlsEnabled,
+              requested: ref.watch(preferencesProvider
+                  .select((p) => p.privilegeAutomationRequested)),
+              statusAsync: privilegeAutomation,
+              onToggle: (enabled) =>
+                  _handlePrivilegeAutomationToggle(context, enabled),
+              onRefresh: () =>
+                  ref.invalidate(vpnPrivilegeAutomationStatusProvider),
+              onVerify: () => _verifyPrivilegeAutomation(context),
+              onRepair: () => _repairPrivilegeAutomation(context),
+            ),
+            const SizedBox(height: AppSpacing.space2),
             _ToggleCard(
               icon: Icons.shield_rounded,
               iconColor: AppColors.error,
@@ -77,6 +104,7 @@ class _SettingsScreenState extends ConsumerState<SettingsScreen> {
               value: ref.watch(preferencesProvider.select((p) => p.killSwitch)),
               onChanged: (v) =>
                   ref.read(preferencesProvider.notifier).setKillSwitch(v),
+              enabled: settingsControlsEnabled,
               isDark: isDark,
             ),
             const SizedBox(height: AppSpacing.space2),
@@ -88,6 +116,7 @@ class _SettingsScreenState extends ConsumerState<SettingsScreen> {
               value: ref
                   .watch(preferencesProvider.select((p) => p.adBlockEnabled)),
               onChanged: (v) => _handleAdBlockChange(context, v),
+              enabled: settingsControlsEnabled,
               isDark: isDark,
             ),
 
@@ -99,6 +128,7 @@ class _SettingsScreenState extends ConsumerState<SettingsScreen> {
               selected: selectedProtocol,
               caps: caps,
               catalog: catalog,
+              enabled: settingsControlsEnabled,
               isDark: isDark,
               onSelect: (p) =>
                   ref.read(vpnStateProvider.notifier).selectProtocol(p),
@@ -114,7 +144,7 @@ class _SettingsScreenState extends ConsumerState<SettingsScreen> {
               results: _diagResults,
               onToggle: (expanded) {
                 setState(() => _diagExpanded = expanded);
-                if (expanded) unawaited(_runDiagnostics());
+                if (expanded && !_diagRunning) unawaited(_runDiagnostics());
               },
               onCopy: () => _copyDiagnostics(context),
             ),
@@ -167,7 +197,80 @@ class _SettingsScreenState extends ConsumerState<SettingsScreen> {
     );
   }
 
+  Future<void> _handlePrivilegeAutomationToggle(
+      BuildContext context, bool enabled) async {
+    if (_reconnecting) return;
+    final prefs = ref.read(preferencesProvider.notifier);
+    final vpnService = ref.read(vpnServiceProvider);
+    await prefs.setPrivilegeAutomationRequested(enabled);
+    if (!context.mounted) return;
+    if (platform.operatingSystem.name.toLowerCase() != 'linux') {
+      ScaffoldMessenger.of(context).showSnackBar(
+        const SnackBar(
+          content: Text('Privilege automation setup is currently Linux-only.'),
+        ),
+      );
+      return;
+    }
+    if (enabled) {
+      if (!context.mounted) return;
+      final confirmed = await showDialog<bool>(
+        context: context,
+        builder: (ctx) => AlertDialog(
+          title: const Text('Enable Automatic VPN Startup'),
+          content: const Text(
+            'SecureWave will perform a one-time system setup on Linux so future VPN starts can run without repeated permission prompts. '
+            'This installs a scoped helper and policy rule limited to SecureWave WireGuard up/down actions.',
+          ),
+          actions: [
+            TextButton(
+              onPressed: () => Navigator.pop(ctx, false),
+              child: const Text('Cancel'),
+            ),
+            FilledButton(
+              onPressed: () => Navigator.pop(ctx, true),
+              child: const Text('Continue'),
+            ),
+          ],
+        ),
+      );
+      if (confirmed != true) {
+        await prefs.setPrivilegeAutomationRequested(false);
+        return;
+      }
+    }
+    final status = enabled
+        ? await vpnService.enablePrivilegeAutomation()
+        : await vpnService.disablePrivilegeAutomation();
+    if (!context.mounted) return;
+    ref.invalidate(vpnPrivilegeAutomationStatusProvider);
+    final message = status.message ??
+        (enabled
+            ? 'Requested privilege automation setup.'
+            : 'Requested privilege automation disable.');
+    ScaffoldMessenger.of(context)
+        .showSnackBar(SnackBar(content: Text(message)));
+  }
+
+  Future<void> _verifyPrivilegeAutomation(BuildContext context) async {
+    final vpnService = ref.read(vpnServiceProvider);
+    final status = await vpnService.verifyPrivilegeAutomation();
+    if (!context.mounted) return;
+    ref.invalidate(vpnPrivilegeAutomationStatusProvider);
+    ScaffoldMessenger.of(context).showSnackBar(
+      SnackBar(content: Text(status.message ?? 'Verification complete.')),
+    );
+  }
+
+  Future<void> _repairPrivilegeAutomation(BuildContext context) async {
+    final prefs = ref.read(preferencesProvider.notifier);
+    await prefs.setPrivilegeAutomationRequested(true);
+    if (!context.mounted) return;
+    await _handlePrivilegeAutomationToggle(context, true);
+  }
+
   void _handleAdBlockChange(BuildContext context, bool v) {
+    if (_reconnecting) return;
     final vpnStatus = ref.read(vpnStateProvider.select((s) => s.status));
     if (vpnStatus == VpnStatus.connected) {
       showDialog<bool>(
@@ -188,7 +291,7 @@ class _SettingsScreenState extends ConsumerState<SettingsScreen> {
       ).then((ok) {
         if (ok == true && mounted && !_reconnecting) {
           ref.read(preferencesProvider.notifier).setAdBlock(v);
-          _reconnecting = true;
+          setState(() => _reconnecting = true);
           unawaited(_reconnectAfterSettingChange());
         }
       });
@@ -204,7 +307,9 @@ class _SettingsScreenState extends ConsumerState<SettingsScreen> {
       if (!mounted) return;
       await notifier.connect();
     } finally {
-      if (mounted) _reconnecting = false;
+      if (mounted) {
+        setState(() => _reconnecting = false);
+      }
     }
   }
 
@@ -244,38 +349,322 @@ class _SettingsScreenState extends ConsumerState<SettingsScreen> {
   }
 
   Future<void> _runDiagnostics() async {
+    if (_diagRunning) return;
     setState(() {
+      _diagRunning = true;
       _diagResults = [
         _DiagResult('Backend reachable', loading: true),
         _DiagResult('Authentication valid', loading: true),
         _DiagResult('VPN service available', loading: true),
+        _DiagResult('Protocol catalog loaded', loading: true),
```

## Patch Extract: securewave_app/lib/core/services/vpn_service.dart

```diff
diff --git a/securewave_app/lib/core/services/vpn_service.dart b/securewave_app/lib/core/services/vpn_service.dart
index 7aa4635..4faeda4 100644
--- a/securewave_app/lib/core/services/vpn_service.dart
+++ b/securewave_app/lib/core/services/vpn_service.dart
@@ -16,6 +16,30 @@ abstract class VpnService {
   bool get isNativeAvailable;
   String? get availabilityMessage;
   Future<VpnCapabilities> getCapabilities();
+  Future<VpnPrivilegeAutomationStatus> getPrivilegeAutomationStatus();
+  Future<VpnPrivilegeAutomationStatus> enablePrivilegeAutomation(
+      {String mode = 'polkit_rule'});
+  Future<VpnPrivilegeAutomationStatus> disablePrivilegeAutomation(
+      {String mode = 'polkit_rule'});
+  Future<VpnPrivilegeAutomationStatus> verifyPrivilegeAutomation(
+      {String mode = 'polkit_rule'});
+  /// Returns the current cumulative traffic counters from the active tunnel.
+  /// [rxBytes] = received bytes, [txBytes] = sent bytes.
+  /// Returns (0, 0) when not connected or the native layer does not support it.
+  Future<({int rxBytes, int txBytes})> getTrafficStats();
+}
+
+/// Cumulative traffic snapshot with a wall-clock timestamp.
+class VpnTrafficSnapshot {
+  const VpnTrafficSnapshot({
+    required this.rxBytes,
+    required this.txBytes,
+    required this.timestamp,
+  });
+
+  final int rxBytes;
+  final int txBytes;
+  final DateTime timestamp;
 }
 
 class VpnServiceException implements Exception {
@@ -87,6 +111,40 @@ class VpnCapabilities {
   );
 }
 
+class VpnPrivilegeAutomationStatus {
+  const VpnPrivilegeAutomationStatus({
+    required this.supported,
+    required this.enabled,
+    this.needsSetup = false,
+    this.canSetup = false,
+    this.backend = 'none',
+    this.message,
+    this.lastError,
+    this.helperInstalled = false,
+    this.ruleInstalled = false,
+    this.pkexecAvailable = false,
+    this.desktopAuthSession = false,
+  });
+
+  final bool supported;
+  final bool enabled;
+  final bool needsSetup;
+  final bool canSetup;
+  final String backend;
+  final String? message;
+  final String? lastError;
+  final bool helperInstalled;
+  final bool ruleInstalled;
+  final bool pkexecAvailable;
+  final bool desktopAuthSession;
+
+  static const unsupported = VpnPrivilegeAutomationStatus(
+    supported: false,
+    enabled: false,
+    backend: 'none',
+  );
+}
+
 class ChannelVpnService implements VpnService {
   ChannelVpnService({
     Duration capabilitiesCacheTtl = const Duration(seconds: 3),
@@ -176,7 +234,7 @@ class ChannelVpnService implements VpnService {
         );
       }
       final capabilities = await getCapabilities();
-      if (!capabilities.supportsProtocol(protocol)) {
+      if (!_isProtocolLocallyConnectable(protocol, capabilities)) {
         _status = VpnStatus.disconnected;
         throw VpnServiceException(
           'protocol_unavailable',
@@ -332,6 +390,181 @@ class ChannelVpnService implements VpnService {
     return fallbackCapabilities;
   }
 
+  @override
+  Future<VpnPrivilegeAutomationStatus> getPrivilegeAutomationStatus() async {
+    if (!_supportsNativeChannel())
+      return VpnPrivilegeAutomationStatus.unsupported;
+    final os = platform.operatingSystem.name.toLowerCase();
+    if (os != 'linux') return VpnPrivilegeAutomationStatus.unsupported;
+    try {
+      final raw = await _channel
+          .invokeMethod<dynamic>('getPrivilegeAutomationStatus')
+          .timeout(const Duration(seconds: 2));
+      if (raw is Map) {
+        final data = Map<String, dynamic>.from(raw);
+        bool b(String key) {
+          final value = data[key];
+          if (value is bool) return value;
+          if (value is num) return value != 0;
+          return value?.toString().toLowerCase() == 'true';
+        }
+
+        return VpnPrivilegeAutomationStatus(
+          supported: b('supported'),
+          enabled: b('enabled'),
+          needsSetup: b('needs_setup'),
+          canSetup: b('can_setup'),
+          backend: (data['backend']?.toString() ?? 'none'),
+          message: data['message']?.toString(),
+          lastError: data['last_error']?.toString(),
+          helperInstalled: b('helper_installed'),
+          ruleInstalled: b('rule_installed'),
+          pkexecAvailable: b('pkexec_available'),
+          desktopAuthSession: b('desktop_auth_session'),
+        );
+      }
+    } catch (error, stackTrace) {
+      AppLogger.warning(
+          'Privilege automation status check failed (using fallback)');
+      AppLogger.error(
+        'getPrivilegeAutomationStatus failed',
+        error: error,
+        stackTrace: stackTrace,
+      );
+    }
+    return const VpnPrivilegeAutomationStatus(
+      supported: true,
+      enabled: false,
+      needsSetup: true,
+      canSetup: false,
+      backend: 'polkit_rule',
+      message: 'Privilege automation setup is not available in this build yet.',
+    );
+  }
+
+  @override
+  Future<VpnPrivilegeAutomationStatus> enablePrivilegeAutomation(
+      {String mode = 'polkit_rule'}) async {
+    if (!_supportsNativeChannel())
+      return VpnPrivilegeAutomationStatus.unsupported;
+    try {
+      final raw = await _channel.invokeMethod<dynamic>(
+        'enablePrivilegeAutomation',
+        <String, dynamic>{'mode': mode},
+      );
+      if (raw is Map) {
+        return VpnPrivilegeAutomationStatus(
+          supported: true,
+          enabled: raw['enabled'] == true,
+          needsSetup: raw['enabled'] != true,
+          canSetup: true,
+          backend: mode,
+          message: raw['message']?.toString(),
+          lastError: raw['error_code']?.toString(),
+        );
+      }
+    } catch (error, stackTrace) {
+      AppLogger.warning('enablePrivilegeAutomation failed (using fallback)');
+      AppLogger.error(
+        'enablePrivilegeAutomation failed',
+        error: error,
+        stackTrace: stackTrace,
+      );
+    }
+    return const VpnPrivilegeAutomationStatus(
+      supported: true,
+      enabled: false,
+      needsSetup: true,
+      canSetup: false,
+      backend: 'polkit_rule',
+      message: 'One-time privilege automation setup is not implemented yet.',
+    );
+  }
+
+  @override
+  Future<VpnPrivilegeAutomationStatus> disablePrivilegeAutomation(
+      {String mode = 'polkit_rule'}) async {
+    if (!_supportsNativeChannel())
+      return VpnPrivilegeAutomationStatus.unsupported;
+    try {
+      final raw = await _channel.invokeMethod<dynamic>(
+        'disablePrivilegeAutomation',
+        <String, dynamic>{'mode': mode},
+      );
+      if (raw is Map) {
+        return VpnPrivilegeAutomationStatus(
+          supported: true,
+          enabled: raw['enabled'] == true,
+          needsSetup: raw['enabled'] != true,
+          canSetup: true,
+          backend: mode,
+          message: raw['message']?.toString(),
+          lastError: raw['error_code']?.toString(),
+        );
+      }
+    } catch (error, stackTrace) {
+      AppLogger.warning('disablePrivilegeAutomation failed (using fallback)');
+      AppLogger.error(
+        'disablePrivilegeAutomation failed',
+        error: error,
+        stackTrace: stackTrace,
+      );
+    }
+    return const VpnPrivilegeAutomationStatus(
+      supported: true,
+      enabled: false,
+      needsSetup: true,
+      canSetup: false,
+      backend: 'polkit_rule',
+      message: 'Privilege automation disable is not implemented yet.',
+    );
+  }
+
+  @override
```

## Patch Extract: routes/vpn.py

```diff
diff --git a/routes/vpn.py b/routes/vpn.py
index 1908c32..aab7ebb 100644
--- a/routes/vpn.py
+++ b/routes/vpn.py
@@ -162,6 +162,8 @@ class ServerInfo(BaseModel):
     status: str
     health_status: str
     supported_protocols: List[str] = Field(default_factory=list, description="Protocols supported by this server")
+    public_ip: Optional[str] = None
+    latency_priority: Optional[int] = None
 
 
 class AllocateConfigRequest(BaseModel):
@@ -197,6 +199,14 @@ class VPNConnectRequest(BaseModel):
         None,
         description="Preferred region or server identifier (best effort)."
     )
+    server_id: Optional[str] = Field(
+        None,
+        description="Exact server_id for connection notification (preferred over region hint).",
+    )
+    protocol: Optional[str] = Field(
+        None,
+        description="Effective protocol used by the client (wireguard/openvpn/ikev2/auto).",
+    )
 
     @field_validator("region")
     @classmethod
@@ -205,6 +215,20 @@ class VPNConnectRequest(BaseModel):
             return None
         return sanitize_region(value)
 
+    @field_validator("server_id")
+    @classmethod
+    def _validate_server_id(cls, value: Optional[str]) -> Optional[str]:
+        if value is None:
+            return None
+        return sanitize_identifier(value, field_name="server_id")
+
+    @field_validator("protocol")
+    @classmethod
+    def _validate_protocol(cls, value: Optional[str]) -> Optional[str]:
+        if value is None:
+            return None
+        return normalize_vpn_protocol(value)
+
 
 class DeviceCreateRequest(BaseModel):
     """Compatibility request to create a VPN device."""
@@ -263,6 +287,34 @@ class ServerListResponse(BaseModel):
     recommended_server_id: Optional[str] = None
 
 
+class RegionProtocolSupport(BaseModel):
+    wireguard: bool
+    openvpn: bool
+    ikev2: bool
+
+
+class RegionRegistryEntry(BaseModel):
+    id: str
+    display_name: str
+    public_ip: str
+    protocol_support: RegionProtocolSupport
+    health_status: str
+    latency_priority: int
+    region: Optional[str] = None
+    city: Optional[str] = None
+    country: Optional[str] = None
+    country_code: Optional[str] = None
+    private_ip: Optional[str] = None
+    hcloud_location: Optional[str] = None
+    tier_restriction: Optional[str] = None  # None=free, 'premium'=premium only
+
+
+class RegionRegistryResponse(BaseModel):
+    regions: List[RegionRegistryEntry]
+    total: int
+    recommended_id: Optional[str] = None
+
+
 class RecommendedServerCandidate(BaseModel):
     server_id: str
     score: float
@@ -307,6 +359,14 @@ class VpnProtocolsResponse(BaseModel):
     protocols: List[VpnProtocolAvailability]
 
 
+class ProtocolCapabilityStatus(BaseModel):
+    wireguard: bool
+    openvpn: bool
+    ikev2: bool
+    server_counts: Dict[str, int]
+    checked_at: str
+
+
 class VpnCredentialProvisionRequest(BaseModel):
     protocol: str = Field(..., description="Protocol to provision (openvpn or ikev2)")
     device_id: Optional[int] = Field(None, description="Existing device ID")
@@ -664,6 +724,172 @@ def _utc_iso(dt: datetime) -> str:
     return dt.astimezone(timezone.utc).isoformat()
 
 
+_COUNTRY_NAME_BY_CODE: dict[str, str] = {
+    "US": "United States",
+    "DE": "Germany",
+    "FI": "Finland",
+    "SG": "Singapore",
+    "NL": "Netherlands",
+    "GB": "United Kingdom",
+    "FR": "France",
+    "CA": "Canada",
+    "MX": "Mexico",
+    "JP": "Japan",
+    "AU": "Australia",
+}
+
+
+def _server_display_location_fields(server: VPNServer) -> tuple[str, str, str, str]:
+    city = str(getattr(server, "city", "") or "").strip()
+    country_code = str(getattr(server, "country_code", "") or "").strip().upper()
+    country = str(getattr(server, "country", "") or "").strip()
+    if len(country) == 2 and country.isalpha():
+        country = _COUNTRY_NAME_BY_CODE.get(country.upper(), country.upper())
+    elif not country and country_code:
+        country = _COUNTRY_NAME_BY_CODE.get(country_code, country_code)
+
+    location = str(getattr(server, "location", "") or "").strip()
+    if not location:
+        parts = [part for part in (city, country or country_code) if part]
+        location = ", ".join(parts) if parts else str(getattr(server, "server_id", "") or "Unknown")
+
+    if not city:
+        city = location.split(",", 1)[0].strip() if location else "Unknown"
+    if not country:
+        country = _COUNTRY_NAME_BY_CODE.get(country_code, country_code or "Unknown")
+    if not country_code and len(country) == 2 and country.isalpha():
+        country_code = country.upper()
+    if not country_code:
+        country_code = "ZZ"
+
+    return location, country, country_code, city
+
+
+def _normalized_region_label(server: VPNServer) -> str:
+    region = str(getattr(server, "region", "") or "").strip()
+    return region or "Other"
+
+
+def _barbados_latency_priority(server: VPNServer) -> int:
+    """
+    Lower number = higher preference for Barbados-first routing.
+
+    Priority order:
+    10  Ashburn / US East
+    20  Miami (if present in future/current fleet)
+    30  Montreal (if present)
+    100 Germany/Frankfurt-class EU fallback
+    150 Other Americas
+    200 Other Europe
+    300 Everything else
+    """
+    hcloud_location = str(getattr(server, "hcloud_location", "") or "").strip().lower()
+    server_id = str(getattr(server, "server_id", "") or "").strip().lower()
+    location = str(getattr(server, "location", "") or "").strip().lower()
+    city = str(getattr(server, "city", "") or "").strip().lower()
+    country_code = str(getattr(server, "country_code", "") or "").strip().upper()
+    region = _normalized_region_label(server).lower()
+
+    tags = f"{hcloud_location} {server_id} {location} {city}"
+    if "ash" in tags or "ashburn" in tags:
+        return 10
+    if "mia" in tags or "miami" in tags:
+        return 20
+    if "yul" in tags or "ymq" in tags or "montreal" in tags or "montréal" in tags:
+        return 30
+
+    if "frankfurt" in tags:
+        return 100
+    if country_code == "DE" or hcloud_location in {"fsn1", "nbg1"}:
+        return 110
+
+    if region in {"caribbean"}:
+        return 120
+    if region == "americas":
+        return 150
+    if region == "europe":
+        return 200
+    if region == "asia-pacific":
+        return 300
+    if region == "middle east & africa":
+        return 320
+    return 400
+
+
+def _server_protocol_support_map(server: VPNServer) -> dict[str, bool]:
+    return {
+        "wireguard": bool(getattr(server, "supports_wireguard", True)),
+        "openvpn": bool(getattr(server, "supports_openvpn", False)),
+        "ikev2": bool(getattr(server, "supports_ikev2", False)),
+    }
+
+
+def _server_health_allows_protocol(server: VPNServer) -> bool:
+    health = str(getattr(server, "health_status", "") or "unknown").strip().lower()
+    return health in {"healthy", "degraded", "unknown"}
+
+
+def _server_protocol_effective_available(server: VPNServer, protocol: str) -> bool:
+    return _server_health_allows_protocol(server) and _server_protocol_material_ready(server, protocol)
+
+
+def _server_protocol_material_ready(server: VPNServer, protocol: str) -> bool:
+    support = _server_protocol_support_map(server)
+    protocol = normalize_vpn_protocol(protocol)
+    if protocol == "wireguard":
+        return support["wireguard"] and bool((getattr(server, "wg_public_key", "") or "").strip()) and bool(
+            (getattr(server, "endpoint", "") or "").strip()
+        )
+    if protocol == "openvpn":
```


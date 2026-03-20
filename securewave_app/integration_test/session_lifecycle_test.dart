import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:securewave_app/app.dart';
import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/debug/automation_keys.dart';
import 'package:securewave_app/features/auth/auth_widgets.dart';
import 'package:securewave_app/features/bootstrap/boot_screen.dart';
import 'package:securewave_app/features/bootstrap/fallback_error_screen.dart';
import 'package:securewave_app/core/services/secure_storage.dart';

const bool _automationEnabled =
    bool.fromEnvironment('SECUREWAVE_UI_AUTOMATION', defaultValue: false);
const bool _mockVpnEnabled =
    bool.fromEnvironment('SECUREWAVE_MOCK_VPN', defaultValue: false);
const String _configuredEmail =
    String.fromEnvironment('SECUREWAVE_E2E_EMAIL', defaultValue: '');
const String _configuredPassword = String.fromEnvironment(
  'SECUREWAVE_E2E_PASSWORD',
  defaultValue: '',
);

const Duration _pollInterval = Duration(milliseconds: 100);

AppConfig? _runtimeConfig;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'desktop session lifecycle remains valid across auth, routing, and vpn transitions',
    (tester) async {
      if (!_automationEnabled) {
        expect(true, isTrue, reason: 'SECUREWAVE_UI_AUTOMATION disabled');
        return;
      }

      expect(
        _configuredEmail.trim().isNotEmpty,
        isTrue,
        reason: 'SECUREWAVE_E2E_EMAIL must be provided for lifecycle login.',
      );
      expect(
        _configuredPassword.isNotEmpty,
        isTrue,
        reason: 'SECUREWAVE_E2E_PASSWORD must be provided for lifecycle login.',
      );

      final config = await _loadAndValidateConfig();
      _runtimeConfig = config;
      debugPrint('[E2E][lifecycle] mock_vpn=$_mockVpnEnabled');
      await _resetPersistedLifecycleAuthState();
      runApp(const ProviderScope(child: SecureWaveApp()));
      await tester.pump();

      await _waitForAppReady(tester, config);
      await _waitForSettledEntrySurface(tester);
      await _ensureSignedOutForDeterministicLogin(tester);
      await _login(
        tester,
        email: _configuredEmail.trim(),
        password: _configuredPassword,
      );
      await _waitForAuthenticatedHome(tester);
      await _ensureDisconnectedBaselineAfterLogin(tester);
      await _assertConnectionControlActionable(tester);

      await _connectFromHomeAndVerify(tester);

      await _openNavigation(tester, 'Settings');
      await _waitForSettingsSurface(tester);
      await _assertShellConnectionState(
        tester,
        'connected',
        reason: 'VPN state did not persist after navigating to Settings.',
      );

      await _openDiagnostics(tester);
      await _waitForDiagnosticsSurface(tester);
      await _assertShellConnectionState(
        tester,
        'connected',
        reason: 'VPN state did not persist after opening Diagnostics.',
      );

      await _openNavigation(tester, 'Account');
      await _waitForAccountSurface(tester);
      await _assertShellConnectionState(
        tester,
        'connected',
        reason: 'VPN state did not persist after navigating to Account.',
      );

      await _openNavigation(tester, 'Home');
      await _waitForAuthenticatedHome(tester, requiredState: 'connected');
      await _disconnectFromHomeAndVerify(tester);
      await _reconnectDuringRouteChangeAndVerify(tester);
      await _openNavigation(tester, 'Home');
      await _waitForAuthenticatedHome(tester, requiredState: 'connected');
      await _disconnectFromHomeAndVerify(tester);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

Future<AppConfig> _loadAndValidateConfig() async {
  final config = await AppConfig.load(forceReload: true);
  debugPrint(
    '[E2E][lifecycle] config source=${config.configSource.name} '
    'apiBaseUrl=${config.apiBaseUrl}',
  );
  expect(
    config.configSource,
    isNot(AppConfigSource.fallback),
    reason: 'Lifecycle E2E aborted: runtime config resolved from fallback.',
  );
  final apiUri = Uri.tryParse(config.apiBaseUrl);
  expect(
    apiUri != null && apiUri.hasScheme && apiUri.host.trim().isNotEmpty,
    isTrue,
    reason:
        'Lifecycle E2E aborted: invalid runtime API base URL `${config.apiBaseUrl}`.',
  );
  return config;
}

Future<void> _resetPersistedLifecycleAuthState() async {
  final storage = SecureStorage();
  await storage.clearTokens();
  await storage.delete(SecureStorage.sessionEmailKey);
  await storage.delete(SecureStorage.selectedServerKey);
  await storage.delete(SecureStorage.vpnProfileConfigKey);
  await storage.delete(SecureStorage.vpnProfileExpiresAtKey);
  await storage.delete(SecureStorage.vpnDeviceIdKey);
}

Future<void> _waitForAppReady(WidgetTester tester, AppConfig config) async {
  await _waitUntil(
    tester,
    () =>
        _isLoginSurfaceVisible() ||
        _isRegisterSurfaceVisible() ||
        _isShellSurfaceVisible() ||
        _finderExists(_fallbackErrorScreenFinder),
    timeout: const Duration(seconds: 60),
    debugLabel: 'app ready',
    debugDetails: () => _surfaceSummary(config),
  );

  if (_finderExists(_fallbackErrorScreenFinder)) {
    fail(
      'App routed to the fallback error screen during launch. '
      '${_surfaceSummary(config)}',
    );
  }
}

Future<void> _waitForSettledEntrySurface(WidgetTester tester) async {
  final endAt = DateTime.now().add(const Duration(seconds: 8));
  DateTime? stableAuthSurfaceSince;

  while (DateTime.now().isBefore(endAt)) {
    await tester.pump(_pollInterval);
    if (_isShellSurfaceVisible()) return;

    if (_isLoginSurfaceVisible() || _isRegisterSurfaceVisible()) {
      stableAuthSurfaceSince ??= DateTime.now();
      if (DateTime.now().difference(stableAuthSurfaceSince) >=
          const Duration(seconds: 1)) {
        return;
      }
    } else {
      stableAuthSurfaceSince = null;
    }
  }

  fail(
    'Timed out waiting for a settled login or shell entry surface. '
    '${_surfaceSummary()}',
  );
}

Future<void> _ensureSignedOutForDeterministicLogin(WidgetTester tester) async {
  if (_isRegisterSurfaceVisible()) {
    await _tap(tester, _registerBackToLoginFinder);
    await _waitForFinder(
      tester,
      _loginSubmitFinder,
      timeout: const Duration(seconds: 20),
      debugLabel: 'login surface after leaving register',
    );
  }

  if (_isShellSurfaceVisible()) {
    await _openNavigation(tester, 'Home');
    await _waitForFinder(
      tester,
      _connectionRingFinder,
      timeout: const Duration(seconds: 20),
      debugLabel: 'home connection ring before sign out',
      debugDetails: _surfaceSummary,
    );
    if (_finderExists(_shellConnectionStateFinder('connected'))) {
      await _tap(tester, _connectionRingFinder);
      await _waitUntil(
        tester,
        () =>
            _finderExists(_shellConnectionStateFinder('disconnecting')) ||
            _finderExists(_shellConnectionStateFinder('disconnected')),
        timeout: const Duration(seconds: 30),
        debugLabel: 'shell disconnect start before sign out',
        debugDetails: _surfaceSummary,
      );
      await _waitForConnectionState(
        tester,
        _shellConnectionStateFinder('disconnected'),
        timeout: const Duration(seconds: 30),
        debugLabel: 'shell disconnected before sign out',
      );
      await _waitForConnectionState(
        tester,
        _connectionStateFinder('disconnected'),
        timeout: const Duration(seconds: 20),
        debugLabel: 'connection control disconnected before sign out',
      );
    } else if (_finderExists(_shellConnectionStateFinder('connecting')) ||
        _finderExists(_shellConnectionStateFinder('disconnecting'))) {
      await _waitForConnectionState(
        tester,
        _shellConnectionStateFinder('disconnected'),
        timeout: const Duration(seconds: 30),
        debugLabel: 'settled disconnected shell state before sign out',
      );
    }

    await _openNavigation(tester, 'Account');
    await _waitForAccountSurface(tester);
    await _tap(tester, _accountSignOutFinder);
    await _waitForFinder(
      tester,
      _accountConfirmSignOutFinder,
      timeout: const Duration(seconds: 20),
      debugLabel: 'confirm sign out dialog',
    );
    await _tap(tester, _accountConfirmSignOutFinder);
  }

  await _waitForStableAuthSurface(tester);
}

Future<void> _login(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  await _waitForStableAuthSurface(tester);
  await _waitForFinder(
    tester,
    _loginEmailFinder,
    timeout: const Duration(seconds: 20),
    debugLabel: 'login email field',
    debugDetails: _surfaceSummary,
  );
  await tester.enterText(_loginEmailFinder, email);
  await tester.pump(_pollInterval);
  await tester.enterText(_loginPasswordFinder, password);
  await tester.pump(_pollInterval);
  await _waitUntil(
    tester,
    () =>
        _textFormFieldValue(_loginEmailFinder) == email &&
        _textFormFieldValue(_loginPasswordFinder) == password,
    timeout: const Duration(seconds: 5),
    debugLabel: 'login form field values applied',
    debugDetails: _surfaceSummary,
  );
  await _tap(tester, _loginSubmitFinder);
  await _waitForAuthOutcome(tester, action: 'login');
}

Future<void> _waitForAuthenticatedHome(
  WidgetTester tester, {
  String? requiredState,
}) async {
  await _waitForFinder(
    tester,
    _shellRootFinder,
    timeout: const Duration(seconds: 40),
    debugLabel: 'navigation shell root',
    debugDetails: _surfaceSummary,
  );
  await _waitForFinder(
    tester,
    _connectionRingFinder,
    timeout: const Duration(seconds: 30),
    debugLabel: 'home connection ring',
    debugDetails: _surfaceSummary,
  );
  if (requiredState != null) {
    await _assertShellConnectionState(
      tester,
      requiredState,
      reason: 'Home shell did not reach the expected `$requiredState` state.',
    );
    await _assertConnectionControlState(
      tester,
      requiredState,
      reason:
          'Home connection control did not expose the expected `$requiredState` state.',
    );
  }
}

Future<void> _ensureDisconnectedBaselineAfterLogin(WidgetTester tester) async {
  if (_finderExists(_shellConnectionStateFinder('connected'))) {
    await _tap(tester, _connectionRingFinder);
    await _waitUntil(
      tester,
      () =>
          _finderExists(_shellConnectionStateFinder('disconnecting')) ||
          _finderExists(_shellConnectionStateFinder('disconnected')),
      timeout: const Duration(seconds: 30),
      debugLabel: 'post-login baseline disconnect start',
      debugDetails: _surfaceSummary,
    );
    await _waitForConnectionState(
      tester,
      _shellConnectionStateFinder('disconnected'),
      timeout: const Duration(seconds: 30),
      debugLabel: 'post-login baseline shell disconnected',
    );
    await _waitForConnectionState(
      tester,
      _connectionStateFinder('disconnected'),
      timeout: const Duration(seconds: 20),
      debugLabel: 'post-login baseline control disconnected',
    );
    return;
  }

  if (_finderExists(_shellConnectionStateFinder('connecting')) ||
      _finderExists(_shellConnectionStateFinder('disconnecting'))) {
    await _waitForConnectionState(
      tester,
      _shellConnectionStateFinder('disconnected'),
      timeout: const Duration(seconds: 30),
      debugLabel: 'post-login baseline settle disconnected',
    );
    await _waitForConnectionState(
      tester,
      _connectionStateFinder('disconnected'),
      timeout: const Duration(seconds: 20),
      debugLabel: 'post-login baseline control settle disconnected',
    );
  }
}

Future<void> _connectFromHomeAndVerify(WidgetTester tester) async {
  await _assertShellConnectionState(
    tester,
    'disconnected',
    reason: 'Expected the shell to start disconnected before connecting.',
  );
  await _assertConnectionControlState(
    tester,
    'disconnected',
    reason:
        'Expected the home connection control to start disconnected before connecting.',
  );

  await _tap(tester, _connectionRingFinder);
  await _waitForConnectionTransition(
    tester,
    fromState: 'disconnected',
    throughState: 'connecting',
    toState: 'connected',
    actionLabel: 'connect',
  );
  await _assertConnectionControlActionable(tester);
}

Future<void> _disconnectFromHomeAndVerify(WidgetTester tester) async {
  await _assertShellConnectionState(
    tester,
    'connected',
    reason: 'Expected the shell to be connected before disconnecting.',
  );
  await _assertConnectionControlState(
    tester,
    'connected',
    reason:
        'Expected the home connection control to be connected before disconnecting.',
  );

  await _tap(tester, _connectionRingFinder);
  await _waitForConnectionTransition(
    tester,
    fromState: 'connected',
    throughState: 'disconnecting',
    toState: 'disconnected',
    actionLabel: 'disconnect',
  );
  await _assertConnectionControlActionable(tester);
}

Future<void> _reconnectDuringRouteChangeAndVerify(WidgetTester tester) async {
  await _assertShellConnectionState(
    tester,
    'disconnected',
    reason: 'Expected the shell to be disconnected before reconnecting.',
  );
  await _assertConnectionControlState(
    tester,
    'disconnected',
    reason:
        'Expected the home connection control to be disconnected before reconnecting.',
  );

  await _tap(tester, _connectionRingFinder);
  await _waitForConnectionState(
    tester,
    _connectionStateFinder('connecting'),
    timeout: const Duration(seconds: 40),
    debugLabel: 'connection control state connecting during reconnect',
  );
  await _waitForConnectionState(
    tester,
    _shellConnectionStateFinder('connecting'),
    timeout: const Duration(seconds: 40),
    debugLabel: 'shell state connecting during reconnect',
  );

  await _openNavigation(tester, 'Settings');
  await _waitForSettingsSurface(tester);
  await _assertShellConnectionState(
    tester,
    'connected',
    reason:
        'Shell did not return to connected after route change during reconnect.',
  );

  await _openNavigation(tester, 'Home');
  await _waitForAuthenticatedHome(tester, requiredState: 'connected');
  await tester.pump(const Duration(seconds: 2));
  expect(
    _finderExists(_shellConnectionStateFinder('connected')),
    isTrue,
    reason: 'Connected state was not stable after reconnect and route change.',
  );
}

Future<void> _waitForConnectionTransition(
  WidgetTester tester, {
  required String fromState,
  required String throughState,
  required String toState,
  required String actionLabel,
}) async {
  await _waitUntil(
    tester,
    () =>
        _finderExists(_connectionStateFinder(throughState)) ||
        _finderExists(_connectionStateFinder(toState)),
    timeout: const Duration(seconds: 45),
    debugLabel:
        '$actionLabel control transition `$throughState` or final `$toState`',
    debugDetails: _surfaceSummary,
  );
  await _waitUntil(
    tester,
    () =>
        _finderExists(_shellConnectionStateFinder(throughState)) ||
        _finderExists(_shellConnectionStateFinder(toState)),
    timeout: const Duration(seconds: 45),
    debugLabel:
        '$actionLabel shell transition `$throughState` or final `$toState`',
    debugDetails: _surfaceSummary,
  );

  await _waitForConnectionState(
    tester,
    _connectionStateFinder(toState),
    timeout: const Duration(seconds: 45),
    debugLabel: '$actionLabel control final state `$toState`',
  );
  await _waitForConnectionState(
    tester,
    _shellConnectionStateFinder(toState),
    timeout: const Duration(minutes: 2),
    debugLabel: '$actionLabel shell final state `$toState`',
  );

  expect(
    _finderExists(_connectionStateFinder(fromState)),
    isFalse,
    reason:
        'Connection control remained in `$fromState` after `$actionLabel` completed.',
  );
}

Future<void> _openNavigation(WidgetTester tester, String label) async {
  final finder = find.byKey(AutomationKeys.navDestinationKey(label));
  await _waitForFinder(
    tester,
    finder,
    timeout: const Duration(seconds: 20),
    debugLabel: 'navigation `$label`',
    debugDetails: _surfaceSummary,
  );
  await _tap(tester, finder);
}

Future<void> _openDiagnostics(WidgetTester tester) async {
  await _waitForFinder(
    tester,
    _diagnosticsTileFinder,
    timeout: const Duration(seconds: 20),
    debugLabel: 'diagnostics entry',
    debugDetails: _surfaceSummary,
  );
  await _tap(tester, _diagnosticsTileFinder);
}

Future<void> _waitForSettingsSurface(WidgetTester tester) async {
  await _waitUntil(
    tester,
    () =>
        _finderExists(_settingsScreenFinder) ||
        _finderExists(_diagnosticsScrollFinder),
    timeout: const Duration(seconds: 20),
    debugLabel: 'settings branch surface',
    debugDetails: _surfaceSummary,
  );
  if (_finderExists(_settingsScreenFinder)) {
    await _waitForFinder(
      tester,
      _diagnosticsTileFinder,
      timeout: const Duration(seconds: 20),
      debugLabel: 'settings diagnostics entry',
    );
  }
}

Future<void> _waitForDiagnosticsSurface(WidgetTester tester) async {
  await _waitForFinder(
    tester,
    _diagnosticsScrollFinder,
    timeout: const Duration(seconds: 30),
    debugLabel: 'diagnostics root scroll',
    debugDetails: _surfaceSummary,
  );
}

Future<void> _waitForAccountSurface(WidgetTester tester) async {
  await _waitForFinder(
    tester,
    _accountScreenFinder,
    timeout: const Duration(seconds: 20),
    debugLabel: 'account screen root',
    debugDetails: _surfaceSummary,
  );
  await _waitForFinder(
    tester,
    _accountSignOutFinder,
    timeout: const Duration(seconds: 20),
    debugLabel: 'account sign out action',
  );
}

Future<void> _waitForStableAuthSurface(WidgetTester tester) async {
  final endAt = DateTime.now().add(const Duration(seconds: 12));
  DateTime? stableSince;

  while (DateTime.now().isBefore(endAt)) {
    await tester.pump(_pollInterval);
    if (_isShellSurfaceVisible()) {
      stableSince = null;
      continue;
    }
    if (_isLoginSurfaceVisible() || _isRegisterSurfaceVisible()) {
      stableSince ??= DateTime.now();
      if (DateTime.now().difference(stableSince) >=
          const Duration(seconds: 1)) {
        await _waitForFinder(
          tester,
          _loginSubmitFinder,
          timeout: const Duration(seconds: 5),
          debugLabel: 'stable login submit button',
          debugDetails: _surfaceSummary,
        );
        return;
      }
      continue;
    }
    stableSince = null;
  }

  fail(
    'Timed out waiting for a stable auth surface before login. '
    '${_surfaceSummary()}',
  );
}

Future<void> _waitForAuthOutcome(
  WidgetTester tester, {
  required String action,
}) async {
  final endAt = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(endAt)) {
    await tester.pump(_pollInterval);
    if (_isShellSurfaceVisible()) return;
    if (_finderExists(_authErrorBannerFinder)) {
      fail(
        'Auth $action failed on the live UI. ${_surfaceSummary()}',
      );
    }
    if (_finderExists(_fallbackErrorScreenFinder)) {
      fail(
        'App crashed into fallback error during auth $action. '
        '${_surfaceSummary()}',
      );
    }
  }
  fail('Timed out waiting for $action completion. ${_surfaceSummary()}');
}

Future<void> _assertConnectionControlActionable(WidgetTester tester) async {
  await _waitForFinder(
    tester,
    _connectionRingFinder,
    timeout: const Duration(seconds: 20),
    debugLabel: 'connection ring action',
  );
  final ring = tester.widget<GestureDetector>(_connectionRingFinder.first);
  expect(
    ring.onTap,
    isNotNull,
    reason:
        'Connection ring is present but not actionable on the active home surface.',
  );
}

Future<void> _assertShellConnectionState(
  WidgetTester tester,
  String state, {
  required String reason,
}) async {
  await _waitForConnectionState(
    tester,
    _shellConnectionStateFinder(state),
    timeout: const Duration(seconds: 40),
    debugLabel: 'shell connection state `$state`',
  );
  expect(
    _finderExists(_shellConnectionStateFinder(state)),
    isTrue,
    reason: reason,
  );
}

Future<void> _assertConnectionControlState(
  WidgetTester tester,
  String state, {
  required String reason,
}) async {
  await _waitForConnectionState(
    tester,
    _connectionStateFinder(state),
    timeout: const Duration(seconds: 40),
    debugLabel: 'connection control state `$state`',
  );
  expect(
    _finderExists(_connectionStateFinder(state)),
    isTrue,
    reason: reason,
  );
}

Future<void> _waitForConnectionState(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
  required String debugLabel,
}) async {
  await _waitUntil(
    tester,
    () {
      if (_finderExists(_shellConnectionStateFinder('error')) ||
          _finderExists(_connectionStateFinder('error'))) {
        fail(
          'Connection entered an error state while waiting for $debugLabel. '
          '${_surfaceSummary()}',
        );
      }
      return _finderExists(finder);
    },
    timeout: timeout,
    debugLabel: debugLabel,
    debugDetails: _surfaceSummary,
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pump(_pollInterval);
}

Future<void> _waitForFinder(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
  required String debugLabel,
  String Function()? debugDetails,
}) async {
  await _waitUntil(
    tester,
    () => _finderExists(finder),
    timeout: timeout,
    debugLabel: debugLabel,
    debugDetails: debugDetails,
  );
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String debugLabel,
  String Function()? debugDetails,
}) async {
  final endAt = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(endAt)) {
    await tester.pump(_pollInterval);
    if (condition()) return;
  }
  final extra = debugDetails?.call();
  fail(
    'Timed out waiting for $debugLabel'
    '${extra == null || extra.isEmpty ? '' : '. $extra'}',
  );
}

bool _finderExists(Finder finder) => finder.evaluate().isNotEmpty;
bool _isLoginSurfaceVisible() => _finderExists(_loginSubmitFinder);
bool _isRegisterSurfaceVisible() => _finderExists(_registerSubmitFinder);
bool _isShellSurfaceVisible() => _finderExists(_shellRootFinder);

String _textFormFieldValue(Finder finder) {
  if (finder.evaluate().isEmpty) {
    return '';
  }
  final field = finder.evaluate().first.widget;
  if (field is! TextFormField) {
    return '';
  }
  return field.controller?.text ?? '';
}

String _surfaceSummary([AppConfig? config]) {
  final effectiveConfig = config ?? _runtimeConfig;
  final visibleTexts = find
      .byType(Text)
      .evaluate()
      .map((element) => (element.widget as Text).data?.trim() ?? '')
      .where((value) => value.isNotEmpty)
      .take(8)
      .toList(growable: false);
  final markers = <String>[
    'configSource=${effectiveConfig?.configSource.name ?? 'unknown'}',
    'apiBaseUrl=${effectiveConfig?.apiBaseUrl ?? 'unknown'}',
    'boot=${_finderExists(_bootScreenFinder)}',
    'fallback=${_finderExists(_fallbackErrorScreenFinder)}',
    'login=${_finderExists(_loginSubmitFinder)}',
    'register=${_finderExists(_registerSubmitFinder)}',
    'shell=${_finderExists(_shellRootFinder)}',
    'settings=${_finderExists(_settingsScreenFinder)}',
    'diagnostics=${_finderExists(_diagnosticsScrollFinder)}',
    'account=${_finderExists(_accountScreenFinder)}',
    'shellDisconnected=${_finderExists(_shellConnectionStateFinder('disconnected'))}',
    'shellConnecting=${_finderExists(_shellConnectionStateFinder('connecting'))}',
    'shellConnected=${_finderExists(_shellConnectionStateFinder('connected'))}',
    'shellDisconnecting=${_finderExists(_shellConnectionStateFinder('disconnecting'))}',
    'shellError=${_finderExists(_shellConnectionStateFinder('error'))}',
    'controlDisconnected=${_finderExists(_connectionStateFinder('disconnected'))}',
    'controlConnecting=${_finderExists(_connectionStateFinder('connecting'))}',
    'controlConnected=${_finderExists(_connectionStateFinder('connected'))}',
    'controlDisconnecting=${_finderExists(_connectionStateFinder('disconnecting'))}',
    'controlError=${_finderExists(_connectionStateFinder('error'))}',
    'authError=${_finderExists(_authErrorBannerFinder)}',
  ];
  final textSummary = visibleTexts.isEmpty
      ? 'visibleTexts=<none>'
      : 'visibleTexts=${visibleTexts.join(' | ')}';
  return '${markers.join(' ')} $textSummary';
}

Finder _connectionStateFinder(String state) =>
    find.byKey(AutomationKeys.connectionStateKey(state));
Finder _shellConnectionStateFinder(String state) =>
    find.byKey(AutomationKeys.shellConnectionStateKey(state));

final Finder _bootScreenFinder = find.byType(BootScreen);
final Finder _fallbackErrorScreenFinder = find.byType(FallbackErrorScreen);
final Finder _loginEmailFinder = find.byKey(AutomationKeys.loginEmailFieldKey);
final Finder _loginPasswordFinder =
    find.byKey(AutomationKeys.loginPasswordFieldKey);
final Finder _loginSubmitFinder =
    find.byKey(AutomationKeys.loginSubmitButtonKey);
final Finder _registerSubmitFinder =
    find.byKey(AutomationKeys.registerSubmitButtonKey);
final Finder _registerBackToLoginFinder =
    find.byKey(AutomationKeys.registerBackToLoginButtonKey);
final Finder _shellRootFinder = find.byKey(AutomationKeys.shellRootScaffoldKey);
final Finder _connectionRingFinder =
    find.byKey(AutomationKeys.connectionRingButtonKey);
final Finder _settingsScreenFinder =
    find.byKey(AutomationKeys.settingsScreenKey);
final Finder _diagnosticsTileFinder =
    find.byKey(AutomationKeys.diagnosticsTileKey);
final Finder _diagnosticsScrollFinder =
    find.byKey(AutomationKeys.diagnosticsRootScrollKey);
final Finder _accountScreenFinder = find.byKey(AutomationKeys.accountScreenKey);
final Finder _accountSignOutFinder =
    find.byKey(AutomationKeys.accountSignOutButtonKey);
final Finder _accountConfirmSignOutFinder =
    find.byKey(AutomationKeys.accountConfirmSignOutButtonKey);
final Finder _authErrorBannerFinder = find.byType(AuthErrorBanner);

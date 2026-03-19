import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/app.dart';
import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/debug/automation_keys.dart';
import 'package:securewave_app/features/auth/auth_widgets.dart';

const bool _automationEnabled =
    bool.fromEnvironment('SECUREWAVE_UI_AUTOMATION', defaultValue: false);
const bool _mockVpnEnabled =
    bool.fromEnvironment('SECUREWAVE_MOCK_VPN', defaultValue: false);
const bool _createAccount =
    bool.fromEnvironment('SECUREWAVE_E2E_CREATE_ACCOUNT', defaultValue: true);
const String _configuredEmail =
    String.fromEnvironment('SECUREWAVE_E2E_EMAIL', defaultValue: '');
const String _configuredPassword = String.fromEnvironment(
    'SECUREWAVE_E2E_PASSWORD',
    defaultValue: 'Securewave123!');

const List<String> _diagnosticsSections = <String>[
  'CONNECTION',
  'PIPELINE',
  'TRAFFIC',
  'PROTOCOLS',
  'LOGS',
];

const List<String> _pipelineSteps = <String>[
  'LOGIN',
  'FETCH_SERVERS',
  'FETCH_PROFILE',
  'PROTOCOL_READY',
  'TUNNEL_START',
  'TUNNEL_ACTIVE',
];

AppConfig? _runtimeConfig;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'live UI smoke flow can run without manual intervention',
    (tester) async {
      if (!_automationEnabled) {
        expect(
          true,
          isTrue,
          reason: 'SECUREWAVE_UI_AUTOMATION disabled',
        );
        return;
      }

      final runId = DateTime.now().millisecondsSinceEpoch;
      final email = _configuredEmail.isNotEmpty
          ? _configuredEmail
          : 'codex.auto.$runId@example.com';
      const password = _configuredPassword;
      debugPrint(
        '[E2E] credentials email=$email password=*** '
        'createAccount=$_createAccount',
      );

      final config = await _loadAndValidateConfig();
      _runtimeConfig = config;
      debugPrint('[E2E] mock_vpn=$_mockVpnEnabled');
      runApp(const ProviderScope(child: SecureWaveApp()));
      await tester.pump();

      await _waitForAppReady(tester, config);
      final startedSignedOut = _isLoginSurfaceVisible();
      if (startedSignedOut) {
        if (_createAccount) {
          final registeredIntoShell = await _registerAccount(
            tester,
            email: email,
            password: password,
          );
          if (registeredIntoShell) {
            await _waitForHome(tester);
            await _signOut(tester);
          } else {
            await _waitForFinder(
              tester,
              _loginSubmitFinder,
              timeout: const Duration(seconds: 30),
              debugLabel: 'login screen after register',
            );
          }
        }
        await _login(tester, email: email, password: password);
        await _waitForHome(tester);
      } else {
        debugPrint(
          '[E2E] existing authenticated session detected; skipping auth forms',
        );
        await _waitForHome(tester);
      }
      await _assertConnectActionReachable(tester);
      await _openNavigation(tester, 'Servers');
      await _waitForServerCatalog(tester);
      await _openNavigation(tester, 'Settings');
      await _openDiagnostics(tester);
      await _assertDiagnosticsSurface(tester);
      await _openNavigation(tester, 'Account');
      await _waitForAccountSurface(tester);
      await tester.pump(const Duration(seconds: 1));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<AppConfig> _loadAndValidateConfig() async {
  final config = await AppConfig.load(forceReload: true);
  debugPrint(
    '[E2E] config source=${config.configSource.name} '
    'apiBaseUrl=${config.apiBaseUrl}',
  );
  expect(
    config.configSource,
    isNot(AppConfigSource.fallback),
    reason: 'E2E aborted: runtime config resolved from fallback. '
        'Packaged .env or dart-define is not loading for desktop runtime.',
  );
  final apiUri = Uri.tryParse(config.apiBaseUrl);
  expect(
    apiUri != null && apiUri.hasScheme && apiUri.host.trim().isNotEmpty,
    isTrue,
    reason: 'E2E aborted: invalid runtime API base URL `${config.apiBaseUrl}`.',
  );
  return config;
}

Future<void> _waitForAppReady(WidgetTester tester, AppConfig config) async {
  await _waitUntil(
    tester,
    () =>
        _isStartupFailureVisible() ||
        _isLoginSurfaceVisible() ||
        _isRegisterSurfaceVisible() ||
        _isShellSurfaceVisible(),
    timeout: const Duration(seconds: 60),
    debugLabel: 'app ready',
    debugDetails: () => _surfaceSummary(tester, config),
  );

  if (_finderExists(_fallbackErrorHeadingFinder)) {
    fail(
      'App routed to fallback error screen instead of auth/shell. '
      '${_surfaceSummary(tester, config)}',
    );
  }
  if (_finderExists(_bootFailureHeadlineFinder) ||
      _finderExists(_bootRetryFinder)) {
    fail(
      'Boot screen reported startup failure. ${_surfaceSummary(tester, config)}',
    );
  }

  if (_isShellSurfaceVisible()) {
    await _waitUntil(
      tester,
      () =>
          _finderExists(_navHomeFinder) || _finderExists(_connectionRingFinder),
      timeout: const Duration(seconds: 20),
      debugLabel: 'navigation shell ready',
      debugDetails: () => _surfaceSummary(tester, config),
    );
    return;
  }

  if (_isLoginSurfaceVisible() || _isRegisterSurfaceVisible()) {
    return;
  }

  fail(
    'App became interactive, but neither auth surface nor navigation shell '
    'was reachable. ${_surfaceSummary(tester, config)}',
  );
}

Future<void> _signOut(WidgetTester tester) async {
  await _openNavigation(tester, 'Account');
  await _waitForFinder(
    tester,
    _accountSignOutFinder,
    timeout: const Duration(seconds: 30),
    debugLabel: 'account sign out button',
  );
  await _tap(tester, _accountSignOutFinder);
  await _waitForFinder(
    tester,
    _accountConfirmSignOutFinder,
    timeout: const Duration(seconds: 20),
    debugLabel: 'confirm sign out button',
  );
  await _tap(tester, _accountConfirmSignOutFinder);
  await _waitForFinder(
    tester,
    _loginSubmitFinder,
    timeout: const Duration(seconds: 30),
    debugLabel: 'login screen after sign out',
  );
}

Future<bool> _registerAccount(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  await _waitForFinder(
    tester,
    _loginCreateAccountFinder,
    timeout: const Duration(seconds: 30),
    debugLabel: 'create account button',
  );
  await _tap(tester, _loginCreateAccountFinder);

  await _waitForFinder(
    tester,
    _registerEmailFinder,
    timeout: const Duration(seconds: 30),
    debugLabel: 'register email field',
  );
  await tester.enterText(_registerEmailFinder, email);
  await tester.enterText(_registerPasswordFinder, password);
  await tester.enterText(_registerConfirmFinder, password);
  await _tap(tester, _registerSubmitFinder);
  return _waitForAuthOutcome(tester, action: 'register');
}

Future<void> _login(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  await _waitForFinder(
    tester,
    _loginSubmitFinder,
    timeout: const Duration(seconds: 30),
    debugLabel: 'login submit button',
  );
  await tester.enterText(_loginEmailFinder, email);
  await tester.enterText(_loginPasswordFinder, password);
  await _tap(tester, _loginSubmitFinder);
  await _waitForAuthOutcome(tester, action: 'login');
}

Future<void> _waitForHome(WidgetTester tester) async {
  await _waitUntil(
    tester,
    () =>
        _finderExists(_shellRootFinder) &&
        _finderExists(_navHomeFinder) &&
        _finderExists(_connectionRingFinder),
    timeout: const Duration(seconds: 40),
    debugLabel: 'home screen',
    debugDetails: () => _surfaceSummary(tester),
  );
}

Future<void> _openNavigation(WidgetTester tester, String label) async {
  final finder = find.byKey(AutomationKeys.navDestinationKey(label));
  await _waitForFinder(
    tester,
    finder,
    timeout: const Duration(seconds: 20),
    debugLabel: 'navigation $label',
  );
  await _tap(tester, finder);
}

Future<void> _assertConnectActionReachable(WidgetTester tester) async {
  await _waitForFinder(
    tester,
    _connectionRingFinder,
    timeout: const Duration(seconds: 20),
    debugLabel: 'connect action',
  );
  final ring = tester.widget<GestureDetector>(_connectionRingFinder.first);
  expect(
    ring.onTap,
    isNotNull,
    reason: 'Connection ring is present but not actionable. '
        'The live connect/disconnect control is not automatable.',
  );
}

Future<void> _waitForServerCatalog(WidgetTester tester) async {
  await _waitUntil(
    tester,
    () =>
        _serverTileFinder.evaluate().isNotEmpty ||
        _finderExists(find.text('Could not load servers')) ||
        _finderExists(find.text('Sign in to view servers')) ||
        _finderExists(find.text('No results')),
    timeout: const Duration(seconds: 30),
    debugLabel: 'server catalog',
    debugDetails: () => _surfaceSummary(tester),
  );
  if (_finderExists(find.text('Could not load servers'))) {
    fail(
      'Server catalog failed to load from the live app. '
      '${_surfaceSummary(tester)}',
    );
  }
  if (_finderExists(find.text('Sign in to view servers'))) {
    fail(
      'Server catalog requires authentication after login completed. '
      '${_surfaceSummary(tester)}',
    );
  }
  if (_finderExists(find.text('No results'))) {
    fail(
      'Server selection loaded but no server rows were visible. '
      '${_surfaceSummary(tester)}',
    );
  }
  expect(
    _serverTileFinder.evaluate().isNotEmpty,
    isTrue,
    reason: 'Servers loaded but no automation-keyed server tiles were visible.',
  );
}

Future<void> _openDiagnostics(WidgetTester tester) async {
  await _waitForFinder(
    tester,
    _diagnosticsTileFinder,
    timeout: const Duration(seconds: 30),
    debugLabel: 'diagnostics entry',
  );
  await _scrollIntoView(
    tester,
    _diagnosticsTileFinder,
    debugLabel: 'diagnostics entry',
  );
  await _tap(tester, _diagnosticsTileFinder);
}

Future<void> _assertDiagnosticsSurface(WidgetTester tester) async {
  await _waitForDiagnosticsReady(tester);
  for (final section in _diagnosticsSections) {
    final sectionFinder = find.text(section);
    await _scrollIntoView(
      tester,
      sectionFinder,
      debugLabel: 'diagnostics section $section',
      preferredScrollable: _diagnosticsScrollFinder,
    );
    await _waitForFinder(
      tester,
      sectionFinder,
      timeout: const Duration(seconds: 20),
      debugLabel: 'diagnostics section $section',
    );
    if (section == 'PIPELINE') {
      for (final step in _pipelineSteps) {
        final stepFinder = find.text(step);
        await _scrollIntoView(
          tester,
          stepFinder,
          debugLabel: 'diagnostics pipeline step $step',
          preferredScrollable: _diagnosticsScrollFinder,
        );
        await _waitForFinder(
          tester,
          stepFinder,
          timeout: const Duration(seconds: 20),
          debugLabel: 'diagnostics pipeline step $step',
        );
      }
    }
  }
  if (_finderExists(find.textContaining('Protocol catalog unavailable.'))) {
    fail(
      'Diagnostics opened, but the protocol catalog failed to load. '
      '${_surfaceSummary(tester)}',
    );
  }
}

Future<void> _waitForDiagnosticsReady(WidgetTester tester) async {
  await _waitForFinder(
    tester,
    _diagnosticsTitleFinder,
    timeout: const Duration(seconds: 30),
    debugLabel: 'diagnostics screen title',
  );
  await _waitUntil(
    tester,
    () =>
        _finderExists(_diagnosticsScrollFinder) &&
        _finderExists(find.text('CONNECTION')) &&
        _finderExists(find.text('PIPELINE')),
    timeout: const Duration(seconds: 30),
    debugLabel: 'diagnostics body ready',
    debugDetails: () => _surfaceSummary(tester),
  );
}

Future<void> _waitForAccountSurface(WidgetTester tester) async {
  await _waitForFinder(
    tester,
    _accountScreenFinder,
    timeout: const Duration(seconds: 20),
    debugLabel: 'account screen root',
    debugDetails: () => _surfaceSummary(tester),
  );
  await _waitForFinder(
    tester,
    _accountSignOutFinder,
    timeout: const Duration(seconds: 20),
    debugLabel: 'account sign out action',
  );
}

Future<bool> _waitForAuthOutcome(
  WidgetTester tester, {
  required String action,
}) async {
  final endAt = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(endAt)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (_isShellSurfaceVisible()) return true;
    if (_finderExists(_authErrorBannerFinder)) {
      fail('Auth $action failed on the live UI. ${_surfaceSummary(tester)}');
    }
    if (action == 'register' &&
        _isLoginSurfaceVisible() &&
        !_isRegisterSurfaceVisible()) {
      return false;
    }
  }
  fail('Timed out waiting for $action completion. ${_surfaceSummary(tester)}');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _scrollIntoView(
  WidgetTester tester,
  Finder finder, {
  required String debugLabel,
  Finder? preferredScrollable,
}) async {
  if (_finderExists(finder)) {
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 250));
    return;
  }
  final scrollable = _resolveScrollableFinder(preferredScrollable);
  if (scrollable == null) {
    fail(
      'Unable to scroll to $debugLabel because no active scrollable surface '
      'was mounted. ${_surfaceSummary(tester)}',
    );
  }
  for (var index = 0; index < 10; index += 1) {
    await tester.drag(scrollable, const Offset(0, -160));
    await tester.pump(const Duration(milliseconds: 250));
    if (_finderExists(finder)) {
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 250));
      return;
    }
  }
  fail(
    'Unable to reveal $debugLabel after scrolling the active diagnostics '
    'surface. ${_surfaceSummary(tester)}',
  );
}

Finder? _resolveScrollableFinder(Finder? preferredScrollable) {
  if (preferredScrollable != null && _finderExists(preferredScrollable)) {
    final nestedScrollable = find.descendant(
      of: preferredScrollable,
      matching: find.byType(Scrollable),
    );
    if (_finderExists(nestedScrollable)) {
      return nestedScrollable.first;
    }
  }
  final anyScrollable = find.byType(Scrollable);
  if (_finderExists(anyScrollable)) {
    return anyScrollable.first;
  }
  return null;
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
    await tester.pump(const Duration(milliseconds: 250));
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
bool _isStartupFailureVisible() =>
    _finderExists(_fallbackErrorHeadingFinder) ||
    _finderExists(_bootFailureHeadlineFinder) ||
    _finderExists(_bootRetryFinder);

String _surfaceSummary(WidgetTester tester, [AppConfig? config]) {
  final effectiveConfig = config ?? _runtimeConfig;
  final visibleTexts = find
      .byType(Text)
      .evaluate()
      .map((element) => (element.widget as Text).data?.trim() ?? '')
      .where((value) => value.isNotEmpty)
      .take(12)
      .toList(growable: false);
  final markers = <String>[
    'configSource=${effectiveConfig?.configSource.name ?? 'unknown'}',
    'apiBaseUrl=${effectiveConfig?.apiBaseUrl ?? 'unknown'}',
    'login=${_finderExists(_loginSubmitFinder)}',
    'register=${_finderExists(_registerSubmitFinder)}',
    'shell=${_finderExists(_shellRootFinder)}',
    'navHome=${_finderExists(_navHomeFinder)}',
    'connectionRing=${_finderExists(_connectionRingFinder)}',
    'diagnosticsTile=${_finderExists(_diagnosticsTileFinder)}',
    'accountSignOut=${_finderExists(_accountSignOutFinder)}',
    'bootFailure=${_finderExists(_bootFailureHeadlineFinder)}',
    'fallbackError=${_finderExists(_fallbackErrorHeadingFinder)}',
  ];
  final textSummary = visibleTexts.isEmpty
      ? 'visibleTexts=<none>'
      : 'visibleTexts=${visibleTexts.join(' | ')}';
  return '${markers.join(' ')} $textSummary';
}

final Finder _loginEmailFinder = find.byKey(AutomationKeys.loginEmailFieldKey);
final Finder _loginPasswordFinder =
    find.byKey(AutomationKeys.loginPasswordFieldKey);
final Finder _loginSubmitFinder =
    find.byKey(AutomationKeys.loginSubmitButtonKey);
final Finder _loginCreateAccountFinder =
    find.byKey(AutomationKeys.loginCreateAccountButtonKey);
final Finder _registerEmailFinder =
    find.byKey(AutomationKeys.registerEmailFieldKey);
final Finder _registerPasswordFinder =
    find.byKey(AutomationKeys.registerPasswordFieldKey);
final Finder _registerConfirmFinder =
    find.byKey(AutomationKeys.registerConfirmFieldKey);
final Finder _registerSubmitFinder =
    find.byKey(AutomationKeys.registerSubmitButtonKey);
final Finder _shellRootFinder = find.byKey(AutomationKeys.shellRootScaffoldKey);
final Finder _navHomeFinder =
    find.byKey(AutomationKeys.navDestinationKey('Home'));
final Finder _connectionRingFinder =
    find.byKey(AutomationKeys.connectionRingButtonKey);
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
final Finder _diagnosticsTitleFinder = find.text('Diagnostics');
final Finder _fallbackErrorHeadingFinder = find.text('Something went wrong');
final Finder _bootFailureHeadlineFinder = find.text('Startup needs attention.');
final Finder _bootRetryFinder = find.widgetWithText(FilledButton, 'Retry');
final Finder _serverTileFinder = find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      key.value.startsWith('automation_server_tile_');
});

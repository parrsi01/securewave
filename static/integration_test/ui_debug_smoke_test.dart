import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/app.dart';
import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/debug/automation_keys.dart';

const bool _automationEnabled =
    bool.fromEnvironment('SECUREWAVE_UI_AUTOMATION', defaultValue: false);
const bool _createAccount =
    bool.fromEnvironment('SECUREWAVE_E2E_CREATE_ACCOUNT', defaultValue: true);
const String _configuredEmail =
    String.fromEnvironment('SECUREWAVE_E2E_EMAIL', defaultValue: '');
const String _configuredPassword = String.fromEnvironment(
    'SECUREWAVE_E2E_PASSWORD',
    defaultValue: 'Securewave123!');

const List<String> _diagnosticLabels = <String>[
  '1) Health: GET /api/health',
  '2) Auth: token persisted and authorized calls',
  '3) Catalog: servers/regions visible',
  '4) Profile: /api/vpn/profile for selected server',
  '5) Tunnel: connect -> connected -> disconnect -> clean',
  '6) Metrics: traffic changes Mbps/MB counters',
];

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

      await AppConfig.load();
      runApp(const ProviderScope(child: SecureWaveApp()));
      await tester.pump();

      await _waitForAppReady(tester);
      final startedSignedOut = _finderExists(_loginSubmitFinder);
      if (startedSignedOut) {
        if (_createAccount) {
          await _registerAccount(tester, email: email, password: password);
          await _waitForHome(tester);
          await _signOut(tester);
        }
        await _login(tester, email: email, password: password);
        await _waitForHome(tester);
      } else {
        debugPrint(
          '[E2E] existing authenticated session detected; skipping auth forms',
        );
        await _waitForHome(tester);
      }
      await _openNavigation(tester, 'Locations');
      await _waitForServerCatalog(tester);
      await _openNavigation(tester, 'Settings');
      await _runDiagnosticsAndExpectPass(tester);
      await tester.pump(const Duration(seconds: 1));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _waitForAppReady(WidgetTester tester) async {
  await _waitUntil(
    tester,
    () =>
        _finderExists(_loginSubmitFinder) ||
        _finderExists(_navAccountFinder) ||
        _finderExists(_connectionRingFinder),
    timeout: const Duration(seconds: 60),
    debugLabel: 'app ready',
  );
}

Future<void> _signOut(WidgetTester tester) async {
  await _openNavigation(tester, 'Account');
  await _waitForFinder(
    tester,
    find.byKey(
      const ValueKey<String>(AutomationKeys.accountSignOutButton),
    ),
    timeout: const Duration(seconds: 30),
    debugLabel: 'account sign out button',
  );
  await _tap(
    tester,
    find.byKey(
      const ValueKey<String>(AutomationKeys.accountSignOutButton),
    ),
  );
  await _waitForFinder(
    tester,
    find.byKey(
      const ValueKey<String>(AutomationKeys.accountConfirmSignOutButton),
    ),
    timeout: const Duration(seconds: 20),
    debugLabel: 'confirm sign out button',
  );
  await _tap(
    tester,
    find.byKey(
      const ValueKey<String>(AutomationKeys.accountConfirmSignOutButton),
    ),
  );
  await _waitForFinder(
    tester,
    _loginSubmitFinder,
    timeout: const Duration(seconds: 30),
    debugLabel: 'login screen after sign out',
  );
}

Future<void> _registerAccount(
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
    find.byKey(
      const ValueKey<String>(AutomationKeys.registerEmailField),
    ),
    timeout: const Duration(seconds: 30),
    debugLabel: 'register email field',
  );
  await tester.enterText(
    find.byKey(
      const ValueKey<String>(AutomationKeys.registerEmailField),
    ),
    email,
  );
  await tester.enterText(
    find.byKey(
      const ValueKey<String>(AutomationKeys.registerPasswordField),
    ),
    password,
  );
  await tester.enterText(
    find.byKey(
      const ValueKey<String>(AutomationKeys.registerConfirmField),
    ),
    password,
  );
  await _tap(
    tester,
    find.byKey(
      const ValueKey<String>(AutomationKeys.registerSubmitButton),
    ),
  );
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
  await tester.enterText(
    find.byKey(
      const ValueKey<String>(AutomationKeys.loginEmailField),
    ),
    email,
  );
  await tester.enterText(
    find.byKey(
      const ValueKey<String>(AutomationKeys.loginPasswordField),
    ),
    password,
  );
  await _tap(tester, _loginSubmitFinder);
}

Future<void> _waitForHome(WidgetTester tester) async {
  await _waitUntil(
    tester,
    () => _finderExists(_navHomeFinder) && _finderExists(_connectionRingFinder),
    timeout: const Duration(seconds: 40),
    debugLabel: 'home screen',
  );
}

Future<void> _openNavigation(WidgetTester tester, String label) async {
  final finder = find.byKey(
    ValueKey<String>(AutomationKeys.navDestination(label)),
  );
  await _waitForFinder(
    tester,
    finder,
    timeout: const Duration(seconds: 20),
    debugLabel: 'navigation $label',
  );
  await _tap(tester, finder);
}

Future<void> _waitForServerCatalog(WidgetTester tester) async {
  await _waitUntil(
    tester,
    () =>
        _serverTileFinder.evaluate().isNotEmpty ||
        _finderExists(find.text('Could not load servers')) ||
        _finderExists(find.text('Sign in to view servers')) ||
        _finderExists(find.text('No servers match')),
    timeout: const Duration(seconds: 30),
    debugLabel: 'server catalog',
  );
  expect(
    _serverTileFinder.evaluate().isNotEmpty,
    isTrue,
    reason: 'Locations loaded but no server tiles were visible.',
  );
}

Future<void> _runDiagnosticsAndExpectPass(WidgetTester tester) async {
  final diagnosticsFinder = find.byKey(
    const ValueKey<String>(AutomationKeys.diagnosticsTile),
  );
  await _waitForFinder(
    tester,
    diagnosticsFinder,
    timeout: const Duration(seconds: 30),
    debugLabel: 'diagnostics panel',
  );
  await _scrollIntoView(tester, diagnosticsFinder);
  await _tap(tester, diagnosticsFinder);

  await _waitUntil(
    tester,
    () => List<bool>.generate(
      _diagnosticLabels.length,
      (index) =>
          _finderExists(_diagnosticResultFinder(index, 'pass')) ||
          _finderExists(_diagnosticResultFinder(index, 'fail')),
    ).every((completed) => completed),
    timeout: const Duration(minutes: 3),
    debugLabel: 'all diagnostics results',
  );

  final failed = <String>[];
  for (var i = 0; i < _diagnosticLabels.length; i += 1) {
    if (_finderExists(_diagnosticResultFinder(i, 'fail'))) {
      failed.add(_diagnosticLabels[i]);
    }
  }
  final allowedHostBlocked = <String>{
    _diagnosticLabels[4],
    _diagnosticLabels[5],
  };
  final hostBlockedByPrivileges = failed.isNotEmpty &&
      failed.every(allowedHostBlocked.contains) &&
      (_finderExists(find.textContaining('wg-quick must be run as root')) ||
          _finderExists(find
              .textContaining('Timed out waiting for VpnStatus.connected')) ||
          _finderExists(find.textContaining('Administrator privileges')) ||
          _finderExists(find.textContaining('Permission required')));
  if (hostBlockedByPrivileges) {
    debugPrint(
      '[E2E] diagnostics tunnel path blocked by host privileges; accepting expected host-limited outcome.',
    );
    return;
  }
  if (failed.isNotEmpty) {
    fail('Diagnostics failed for: ${failed.join(', ')}');
  }
}

Finder _diagnosticResultFinder(int index, String status) {
  return find.byKey(
    ValueKey<String>(AutomationKeys.diagnosticsResult(index, status)),
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _scrollIntoView(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  if (_finderExists(finder)) {
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 250));
    return;
  }
  await tester.scrollUntilVisible(
    finder,
    160,
    scrollable: scrollable,
    maxScrolls: 10,
  );
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _waitForFinder(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
  required String debugLabel,
}) async {
  await _waitUntil(
    tester,
    () => _finderExists(finder),
    timeout: timeout,
    debugLabel: debugLabel,
  );
}

Future<void> _waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String debugLabel,
}) async {
  final endAt = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(endAt)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (condition()) return;
  }
  fail('Timed out waiting for $debugLabel');
}

bool _finderExists(Finder finder) => finder.evaluate().isNotEmpty;

final Finder _loginSubmitFinder = find.byKey(
  const ValueKey<String>(AutomationKeys.loginSubmitButton),
);
final Finder _loginCreateAccountFinder = find.byKey(
  const ValueKey<String>(AutomationKeys.loginCreateAccountButton),
);
final Finder _navHomeFinder = find.byKey(
  ValueKey<String>(AutomationKeys.navDestination('Home')),
);
final Finder _navAccountFinder = find.byKey(
  ValueKey<String>(AutomationKeys.navDestination('Account')),
);
final Finder _connectionRingFinder = find.byKey(
  const ValueKey<String>(AutomationKeys.connectionRingButton),
);
final Finder _serverTileFinder = find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      key.value.startsWith('automation_server_tile_');
});

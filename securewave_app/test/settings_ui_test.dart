import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/app.dart';
import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/constants/app_constants.dart';
import 'package:securewave_app/core/models/server_region.dart';
import 'package:securewave_app/core/models/user_account.dart';
import 'package:securewave_app/core/models/user_plan.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/services/secure_storage.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
import 'package:securewave_app/services/api_client.dart';
import 'package:securewave_app/services/external_links.dart';

class _RecordingStorage extends SecureStorage {
  _RecordingStorage(this.events);

  final List<String> events;
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> getAccessToken() async => 'opaque-example.test-session';

  @override
  Future<void> saveToken(String accessToken) async {}

  @override
  Future<void> clearToken() async {}

  @override
  Future<void> clearVpnRuntimeState() async {
    events.add('runtime-clear');
    values.clear();
  }

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> saveString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _RecordingSession extends AuthSession {
  _RecordingSession(this.events, SecureStorage storage)
      : super(storage: storage);

  final List<String> events;
  bool authenticated = true;

  @override
  bool get isInitialized => true;

  @override
  bool get isAuthenticated => authenticated;

  @override
  String? get accessToken =>
      authenticated ? 'opaque-example.test-session' : null;

  @override
  Future<void> clearSession() async {
    events.add('session-clear');
    authenticated = false;
    notifyListeners();
  }
}

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient(this.events, AuthSession session)
      : super(
          const AppConfig(
            apiBaseUrl: 'https://api.example.test',
            demoMode: false,
          ),
          session: session,
        );

  final List<String> events;

  @override
  Future<void> logout() async {
    events.add('api-logout');
  }
}

class _RecordingLinks extends ExternalLinksService {
  String? openedUrl;

  @override
  Future<void> openUrl(String url) async {
    openedUrl = url;
  }
}

class _RecordingVpnNotifier extends VpnStateNotifier {
  _RecordingVpnNotifier(super.ref, this.events, VpnState initial) {
    state = initial;
  }

  final List<String> events;

  @override
  Future<void> disconnect() async {
    events.add('disconnect');
    state = state.copyWith(status: VpnStatus.disconnected);
  }

  @override
  Future<void> selectServer(String? serverId) async {
    events.add('selection-clear');
    state = state.copyWith(clearSelectedServer: serverId == null);
  }
}

const _account = UserAccount(
  id: 42,
  email: 'settings@example.test',
  isActive: true,
  emailVerified: true,
  subscriptionStatus: 'Free',
);

const _plan = UserPlan(
  name: 'Free',
  isPremium: false,
  dataCapGb: 5,
  usedGb: 2,
);

const _server = ServerRegion(
  id: 'beta-one',
  name: 'SecureWave Beta',
  location: 'Nuremberg, Germany',
  health: 'healthy',
  supportedProtocols: <String>['wireguard'],
);

void main() {
  testWidgets('Settings renders safe account identity and 5 GB allowance',
      (tester) async {
    final harness = await _pumpSettings(tester);
    addTearDown(harness.dispose);

    for (final value in const [
      'settings@example.test',
      'Active',
      'Verified',
      'Subscription',
      'Free',
      '2 GB',
      '3 GB remaining of 5 GB',
      '5 GB',
    ]) {
      expect(find.text(value), findsWidgets);
    }

    final rendered = _renderedText(tester);
    for (final forbidden in const [
      '42',
      'password',
      'access_token',
      'refresh_token',
      'cookie',
      'csrf',
      'PrivateKey',
      '[Interface]',
      '[Peer]',
    ]) {
      expect(rendered, isNot(contains(forbidden)));
    }
  });

  testWidgets('Settings presents inactive and unverified identity safely',
      (tester) async {
    final harness = await _pumpSettings(
      tester,
      account: const UserAccount(
        id: 7,
        email: 'inactive@example.test',
        isActive: false,
        emailVerified: false,
        subscriptionStatus: 'Free',
      ),
    );
    addTearDown(harness.dispose);

    expect(find.text('Inactive'), findsOneWidget);
    expect(find.text('Unverified'), findsOneWidget);
  });

  testWidgets('Settings clamps exhausted allowance', (tester) async {
    final harness = await _pumpSettings(
      tester,
      plan: const UserPlan(
        name: 'Free',
        isPremium: false,
        dataCapGb: 5,
        usedGb: 8,
      ),
    );
    addTearDown(harness.dispose);

    expect(find.text('0 GB remaining of 5 GB'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('allowance-progress')),
          )
          .value,
      1,
    );
  });

  testWidgets('Settings shows account and plan loading and error states',
      (tester) async {
    final accountGate = Completer<UserAccount>().future;
    final planGate = Completer<UserPlan>().future;
    var harness = await _pumpSettings(
      tester,
      accountLoadingFuture: accountGate,
      planLoadingFuture: planGate,
    );
    addTearDown(harness.dispose);
    expect(
        find.byKey(const ValueKey('settings-account-loading')), findsOneWidget);
    expect(find.text('Loading allowance'), findsOneWidget);

    harness = await _pumpSettings(
      tester,
      accountError: StateError('Account unavailable.'),
      planError: StateError('Plan unavailable.'),
    );
    addTearDown(harness.dispose);
    expect(
        find.byKey(const ValueKey('settings-account-error')), findsOneWidget);
    expect(find.text('Allowance unavailable'), findsOneWidget);
  });

  testWidgets('diagnostics and account portal use existing actions',
      (tester) async {
    final harness = await _pumpSettings(tester, demoMode: true);
    addTearDown(harness.dispose);

    final diagnostics = find.byKey(
      const ValueKey('settings-diagnostics-action'),
    );
    await tester.ensureVisible(diagnostics);
    await tester.tap(diagnostics);
    await tester.pumpAndSettle();
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('https://api.example.test'), findsOneWidget);
    expect(find.text('WireGuard'), findsWidgets);
    expect(find.text('Active — simulated only'), findsOneWidget);
    expect(find.text(_expectedPlatformLabel(defaultTargetPlatform)),
        findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    final portal = find.byKey(const ValueKey('account-portal-action'));
    await tester.ensureVisible(portal);
    await tester.tap(portal);
    await tester.pump();
    expect(harness.links.openedUrl, AppConstants.portalUrlFallback);
  });

  testWidgets('sign out disconnects before clearing the session',
      (tester) async {
    final harness = await _pumpSettings(
      tester,
      vpnState: const VpnState(
        status: VpnStatus.connected,
        selectedServerId: 'beta-one',
      ),
    );
    addTearDown(harness.dispose);

    final signOut = find.byKey(const ValueKey('sign-out-action'));
    await tester.ensureVisible(signOut);
    await tester.tap(signOut);
    await tester.pumpAndSettle();

    expect(
        harness.events,
        containsAll(<String>[
          'disconnect',
          'selection-clear',
          'api-logout',
          'session-clear',
          'runtime-clear',
        ]));
    expect(
      harness.events.indexOf('disconnect'),
      lessThan(harness.events.indexOf('session-clear')),
    );
    expect(find.byKey(const ValueKey('authentication-title')), findsOneWidget);
  });

  testWidgets('sign out is disabled during VPN transitions', (tester) async {
    final harness = await _pumpSettings(
      tester,
      vpnState: const VpnState(status: VpnStatus.connecting),
    );
    addTearDown(harness.dispose);

    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('sign-out-action')),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.text('Wait for the current VPN transition before signing out.'),
      findsOneWidget,
    );
  });

  testWidgets('Settings has no overflow on mobile and desktop', (tester) async {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      final harness = await _pumpSettings(tester, size: size);
      addTearDown(harness.dispose);
      expect(tester.takeException(), isNull);
    }
  });
}

class _SettingsHarness {
  const _SettingsHarness({
    required this.container,
    required this.events,
    required this.links,
  });

  final ProviderContainer container;
  final List<String> events;
  final _RecordingLinks links;

  void dispose() => container.dispose();
}

Future<_SettingsHarness> _pumpSettings(
  WidgetTester tester, {
  UserAccount account = _account,
  UserPlan plan = _plan,
  Future<UserAccount>? accountLoadingFuture,
  Future<UserPlan>? planLoadingFuture,
  Object? accountError,
  Object? planError,
  VpnState vpnState = const VpnState(),
  bool demoMode = false,
  Size size = const Size(1280, 800),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final events = <String>[];
  final storage = _RecordingStorage(events);
  final session = _RecordingSession(events, storage);
  final api = _RecordingApiClient(events, session);
  final links = _RecordingLinks();
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWith(
        (_) => AppConfig(
          apiBaseUrl: 'https://api.example.test',
          demoMode: demoMode,
        ),
      ),
      secureStorageProvider.overrideWithValue(storage),
      authSessionProvider.overrideWith((_) => session),
      apiClientProvider.overrideWithValue(api),
      externalLinksProvider.overrideWithValue(links),
      currentUserProvider.overrideWith((_) async {
        if (accountLoadingFuture != null) return accountLoadingFuture;
        if (accountError != null) throw accountError;
        return account;
      }),
      userPlanProvider.overrideWith((_) async {
        if (planLoadingFuture != null) return planLoadingFuture;
        if (planError != null) throw planError;
        return plan;
      }),
      serversProvider.overrideWith((_) async => const [_server]),
      vpnStateProvider.overrideWith(
        (ref) => _RecordingVpnNotifier(ref, events, vpnState),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      key: UniqueKey(),
      container: container,
      child: const SecureWaveApp(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  if (size.width < 760) {
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('mobile-navigation')),
        matching: find.text('Settings'),
      ),
    );
  } else {
    await tester.tap(find.byKey(const ValueKey('desktop-nav-settings')));
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  return _SettingsHarness(
    container: container,
    events: events,
    links: links,
  );
}

String _renderedText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((widget) => widget.data ?? '')
    .join('\n');

String _expectedPlatformLabel(TargetPlatform platform) => switch (platform) {
      TargetPlatform.linux => 'Linux desktop',
      TargetPlatform.android => 'Android device',
      TargetPlatform.iOS => 'iOS device',
      TargetPlatform.macOS => 'macOS desktop',
      TargetPlatform.windows => 'Windows desktop',
      TargetPlatform.fuchsia => 'Fuchsia device',
    };

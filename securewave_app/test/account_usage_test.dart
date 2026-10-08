import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securewave_app/services/account_usage.dart';
import 'package:securewave_app/services/api_service.dart';
import 'package:securewave_app/ui/monthly_usage.dart';
import 'package:securewave_app/ui/settings_view.dart';

import 'support/ui_fixtures.dart';

Map<String, dynamic> summary(
        {int user = 1,
        int bytes = 700000,
        int saved = 700000,
        String start = '2026-10-01T00:00:00Z',
        String end = '2026-11-01T00:00:00Z',
        bool finished = false,
        int session = 10}) =>
    {
      'user_id': user,
      'email': 'user$user@example.test',
      'plan_id': 'free',
      'plan_name': 'Free',
      'used_bytes': bytes,
      'quota_bytes': 5000000000,
      'period_start': start,
      'period_end': end,
      'last_session': {
        'session_id': session,
        'bytes_sent': 0,
        'bytes_received': saved,
        'disconnected_at': finished ? '2026-10-08T00:00:00Z' : null,
        'recording_quality': finished ? 'complete' : 'recording'
      },
      'tracked_sessions': [
        {
          'session_id': session,
          'bytes_sent': 0,
          'bytes_received': saved,
          'disconnected_at': finished ? '2026-10-08T00:00:00Z' : null,
          'recording_quality': 'recording'
        }
      ],
    };

class UsageApi extends ApiService {
  UsageApi(this.data);
  Map<String, dynamic> data;
  bool offline = false;
  List<int> requested = [];
  @override
  Future<MonthlyAccountUsage> fetchMonthlyUsage(
      {List<int> sessionIds = const []}) async {
    requested = sessionIds;
    if (offline) throw const ApiException('offline');
    return MonthlyAccountUsage.fromJson(data);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  setUpAll(loadFixtureFonts);

  test('decimal formatting agrees with the exact 5 GB allowance', () {
    expect(formatDataBytes(760870), '760.87 KB');
    expect(formatDataBytes(5000000000), '5.00 GB');
    expect(formatDataBytes(0), '0 B');
  });

  test('live cumulative preview counts only the unacknowledged difference',
      () async {
    final api = UsageApi(summary());
    final store = AccountUsageStore(api);
    await store.initialize();
    await store.observe(10, 0, 760870);
    expect(store.usedBytes, 760870);
    expect(store.pendingBytes, 60870);
    api.data = summary(bytes: 750000, saved: 750000);
    await store.refresh();
    expect(store.usedBytes, 760870);
    expect(store.pendingBytes, 10870);
    api.data = summary(bytes: 760870, saved: 760870, finished: true);
    await store.observe(10, 0, 760870, finalized: true);
    await store.refresh();
    expect(store.usedBytes, 760870);
    expect(store.pendingBytes, 0);
    store.dispose();
  });

  test('disconnect cache survives logout/login while reporting retries',
      () async {
    final api = UsageApi(summary());
    final first = AccountUsageStore(api);
    await first.initialize();
    await first.observe(10, 0, 760870, finalized: true);
    first.dispose();
    final relogin = AccountUsageStore(api);
    await relogin.initialize();
    expect(relogin.usedBytes, 760870);
    expect(api.requested, [10]);
    api.offline = true;
    await relogin.refresh();
    expect(relogin.usedBytes, 760870);
    expect(relogin.notice, contains('Showing saved usage'));
    api.offline = false;
    api.data = summary(bytes: 760890, saved: 760890, finished: true);
    await relogin.refresh();
    expect(relogin.usedBytes, 760890); // Server final tail wins.
    expect(relogin.pendingBytes, 0);
    relogin.dispose();
  });

  test('account caches and tracked sessions cannot leak to another account',
      () async {
    final one = AccountUsageStore(UsageApi(summary()));
    await one.initialize();
    await one.observe(10, 0, 760870, finalized: true);
    one.dispose();
    final two = AccountUsageStore(
        UsageApi(summary(user: 2, bytes: 1200, saved: 1200, session: 20)));
    await two.initialize();
    expect(two.usedBytes, 1200);
    expect(two.summary!.email, 'user2@example.test');
    await two.observe(10, 0, 999999,
        finalized: true); // Foreign ID is not in owner-scoped response.
    expect(two.usedBytes, 1200);
    two.dispose();
  });

  test(
      'a new UTC month drops old pending previews and starts the new allowance',
      () async {
    final api = UsageApi(summary());
    final store = AccountUsageStore(api);
    await store.initialize();
    await store.observe(10, 0, 760870, finalized: true);
    api.data = summary(
        bytes: 0,
        saved: 760870,
        start: '2026-11-01T00:00:00Z',
        end: '2026-12-01T00:00:00Z',
        finished: true);
    await store.refresh();
    expect(store.usedBytes, 0);
    expect(store.pendingBytes, 0);
    expect(store.summary!.lastSession!.total,
        760870); // Last session is still saved.
    store.dispose();
  });

  testWidgets('bar retains nonzero disconnected total and is accessible',
      (tester) async {
    final store = AccountUsageStore(
        UsageApi(summary(bytes: 760870, saved: 760870, finished: true)));
    await store.initialize();
    await tester.pumpWidget(fixtureHost(
        Scaffold(body: MonthlyUsageView(store: store, onRefresh: () {}))));
    expect(find.text('760.87 KB of 5 GB used'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byKey(const ValueKey('monthly-usage-bar')))
            .value,
        closeTo(760870 / 5000000000, 0.00000001));
    store.dispose();
  });

  testWidgets('loading/unavailable is never presented as an empty allowance',
      (tester) async {
    final api = UsageApi(summary())..offline = true;
    final store = AccountUsageStore(api);
    await tester.pumpWidget(fixtureHost(
        Scaffold(body: MonthlyUsageView(store: store, onRefresh: () {}))));
    expect(find.text('Loading monthly usage…'), findsOneWidget);
    await store.initialize();
    await tester.pumpWidget(fixtureHost(
        Scaffold(body: MonthlyUsageView(store: store, onRefresh: () {}))));
    expect(find.text('Monthly usage unavailable'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    store.dispose();
  });

  testWidgets('settings navigation and refresh have named accessible actions',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final store = AccountUsageStore(UsageApi(summary()));
    await store.initialize();
    await tester.pumpWidget(fixtureHost(SettingsView(
        store: store,
        location: 'Germany',
        connectionStatus: 'Disconnected',
        onBack: () {},
        onRefresh: () {})));
    expect(find.bySemanticsLabel('Back to VPN'), findsOneWidget);
    expect(find.bySemanticsLabel('Refresh monthly usage'), findsOneWidget);
    semantics.dispose();
    store.dispose();
  });

  for (final size in [
    const Size(320, 480),
    const Size(900, 680),
    const Size(1600, 900)
  ]) {
    testWidgets('settings is readable at $size and double text scale',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AccountUsageStore(
          UsageApi(summary(bytes: 760870, saved: 760870, finished: true)));
      await store.initialize();
      var back = 0;
      await tester.pumpWidget(fixtureHost(
          SettingsView(
              store: store,
              location: 'Germany',
              connectionStatus: 'Disconnected',
              onBack: () => back++,
              onRefresh: () {}),
          scale: 2));
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('user1@example.test'), findsOneWidget);
      expect(find.text('WireGuard'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Back to VPN'));
      expect(back, 1);
      store.dispose();
    });
  }
}

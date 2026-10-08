import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securewave_app/services/account_usage.dart';
import 'package:securewave_app/services/vpn_service.dart';
import 'package:securewave_app/ui/connection_view.dart';
import 'package:securewave_app/ui/monthly_usage.dart';
import 'package:securewave_app/ui/settings_view.dart';

import 'account_usage_test.dart' show UsageApi, summary;
import 'support/ui_fixtures.dart';

void main() {
  setUpAll(loadFixtureFonts);
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final size in [
    const Size(1280, 720),
    const Size(900, 600),
    const Size(640, 680),
    const Size(390, 844)
  ]) {
    for (final settings in [false, true]) {
      testWidgets(
          '${settings ? 'Settings' : 'Home'} fits $size without scrolling',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = AccountUsageStore(
            UsageApi(summary(bytes: 760870, saved: 760870, finished: true)));
        await store.initialize();
        addTearDown(store.dispose);
        final page = settings
            ? SettingsView(
                store: store,
                location: 'Nuremberg, Germany',
                connectionStatus: 'Disconnected',
                onBack: () {},
                onRefresh: () {})
            : ConnectionView(
                status: VpnStatus.disconnected,
                canDisconnect: false,
                transitioning: false,
                serverLabel: 'Nuremberg, Germany',
                download: '760.87 KB',
                upload: '75.82 KB',
                countersAvailable: true,
                recordingNotice: 'Session transfer saved.',
                sessionLabel: 'Last session transfer',
                monthlyUsage: MonthlyUsageView(
                    store: store, onRefresh: () {}, compact: true),
                onSettings: () {},
                onToggle: () {},
                onLogout: () {});
        await tester.pumpWidget(fixtureHost(page));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final scroll
            in tester.stateList<ScrollableState>(find.byType(Scrollable))) {
          expect(scroll.position.maxScrollExtent, 0,
              reason: 'All page content must fit at $size');
        }
        expect(find.text('760.87 KB of 5 GB used'), findsOneWidget);
        final bar =
            tester.getRect(find.byKey(const ValueKey('monthly-usage-bar')));
        expect(bar.bottom, lessThanOrEqualTo(size.height));
        if (settings) expect(find.text('1.0.0'), findsOneWidget);
      });
    }
  }
  testWidgets('large accessibility text can scroll to every Settings value',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AccountUsageStore(UsageApi(summary()));
    await store.initialize();
    addTearDown(store.dispose);
    await tester.pumpWidget(fixtureHost(
        SettingsView(
            store: store,
            location: 'Nuremberg, Germany',
            connectionStatus: 'Disconnected',
            onBack: () {},
            onRefresh: () {}),
        scale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text(
        'Upload and download count toward your allowance. Usage stays saved after disconnecting or signing out.'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        greaterThan(0));
  });
}

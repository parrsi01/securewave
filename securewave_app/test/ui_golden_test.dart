import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securewave_app/services/vpn_service.dart';
import 'package:securewave_app/ui/auth_form.dart';

import 'support/ui_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFixtureFonts);

  final cases = <String, Widget Function()>{
    'boot': () => const BootView(),
    'sign_in': () => const AuthFixture(),
    'create_account': () => const AuthFixture(registering: true),
    'sign_in_validation': () => const AuthFixture(validation: true),
    'registration_validation': () =>
        const AuthFixture(registering: true, validation: true),
    'auth_error': () => const AuthFixture(error: 'Invalid email or password.'),
    'session_expiry': () => const AuthFixture(
        notice: 'Your session has expired. Sign in to continue.'),
    'registration_success': () =>
        const AuthFixture(notice: 'Account created. Sign in to continue.'),
    'sign_in_busy': () => const AuthFixture(busy: true),
    'create_account_busy': () =>
        const AuthFixture(registering: true, busy: true),
    'disconnected': () => homeFixture(),
    'connecting': () =>
        homeFixture(status: VpnStatus.connecting, available: false),
    'connected': () => homeFixture(status: VpnStatus.connected),
    'disconnecting': () => homeFixture(status: VpnStatus.disconnecting),
    'error_connect': () =>
        homeFixture(status: VpnStatus.error, error: 'unknown'),
    'error_disconnect': () => homeFixture(
        status: VpnStatus.error,
        canDisconnect: true,
        error: 'Could not disconnect the WireGuard tunnel.'),
    'helper_error': () => homeFixture(
        status: VpnStatus.error,
        error: 'The Linux WireGuard helper is unavailable.'),
    'backend_error': () => homeFixture(
        status: VpnStatus.error,
        error:
            'Unable to reach SecureWave. Check your connection and try again.'),
    'transfer_nonzero': () => homeFixture(
        status: VpnStatus.connected, download: '2.0 MB', upload: '512.0 KB'),
    'transfer_unavailable': () =>
        homeFixture(status: VpnStatus.connected, available: false),
    'recording_pending': () => homeFixture(
        status: VpnStatus.connected,
        recordingNotice: 'Measured usage is awaiting server confirmation.'),
    'recording_gap': () => homeFixture(
        status: VpnStatus.connected,
        recordingNotice: 'Usage recording contains a measurement gap.'),
    'long_feedback': () => const AuthFixture(
        error:
            'SecureWave could not authorize account creation. Please try again later. SecureWave could not authorize account creation. Please try again later.'),
  };

  void capture(
    String name,
    Widget Function() page, {
    Size size = const Size(900, 680),
    double scale = 1,
    bool reduced = true,
    int focusTabs = 0,
    String? scrollKey,
  }) {
    testWidgets('fixture-based $name', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(fixtureHost(
        RepaintBoundary(key: const ValueKey('capture'), child: page()),
        scale: scale,
        reducedMotion: reduced,
      ));
      await tester.pump(const Duration(milliseconds: 240));
      for (var i = 0; i < focusTabs; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 200));
      if (scrollKey != null) {
        await tester.ensureVisible(find.byKey(ValueKey(scrollKey)));
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(tester.takeException(), isNull);
      await expectLater(find.byKey(const ValueKey('capture')),
          matchesGoldenFile('goldens/fixture_$name.png'));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final entry in cases.entries) {
    capture('${entry.key}_900x680', entry.value);
  }
  for (final viewport in [
    const Size(1280, 720),
    const Size(1600, 900),
    const Size(640, 480),
    const Size(390, 844),
    const Size(320, 480)
  ]) {
    final suffix = '${viewport.width.toInt()}x${viewport.height.toInt()}';
    for (final name in [
      'sign_in',
      'create_account',
      'disconnected',
      'connecting',
      'connected',
      'disconnecting',
      'error_disconnect'
    ]) {
      capture('${name}_$suffix', cases[name]!, size: viewport);
    }
  }
  for (final scale in [1.5, 2.0]) {
    for (final viewport in [const Size(900, 680), const Size(320, 480)]) {
      final suffix =
          '${viewport.width.toInt()}x${viewport.height.toInt()}_text${(scale * 100).toInt()}';
      for (final name in ['create_account', 'disconnecting', 'error_connect']) {
        capture('${name}_$suffix', cases[name]!, size: viewport, scale: scale);
      }
    }
  }
  capture('circle_focus', cases['disconnected']!, focusTabs: 2);
  capture('logout_focus', cases['disconnected']!, focusTabs: 1);
  capture('auth_submit_focus', cases['sign_in']!, focusTabs: 3);
  capture('connecting_motion', cases['connecting']!, reduced: false);
  capture('disconnecting_motion', cases['disconnecting']!, reduced: false);
  capture('compact_large_action_scrolled', cases['disconnecting']!,
      size: const Size(320, 480), scale: 2, scrollKey: 'connection-action');
  capture('compact_large_auth_scrolled', cases['create_account']!,
      size: const Size(320, 480), scale: 2, scrollKey: 'auth-submit');
}

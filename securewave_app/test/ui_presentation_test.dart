import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:securewave_app/app.dart';
import 'package:securewave_app/services/vpn_service.dart';
import 'package:securewave_app/ui/connection_view.dart';
import 'package:securewave_app/ui/theme.dart';

import 'support/ui_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFixtureFonts);
  Future<void> size(WidgetTester tester, Size viewport) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final entry in [
    (VpnStatus.disconnected, false, 'Connect'),
    (VpnStatus.connecting, false, 'Connecting'),
    (VpnStatus.connected, true, 'Disconnect'),
    (VpnStatus.disconnecting, true, 'Disconnecting'),
    (VpnStatus.error, false, 'Try again'),
    (VpnStatus.error, true, 'Disconnect'),
  ]) {
    testWidgets('${entry.$1.name}: ${entry.$3} uses supplied callback safely',
        (tester) async {
      await size(tester, const Size(900, 680));
      var toggles = 0;
      var logouts = 0;
      await tester.pumpWidget(fixtureHost(homeFixture(
        status: entry.$1,
        canDisconnect: entry.$2,
        onToggle: () => toggles++,
        onLogout: () => logouts++,
      )));
      final button = tester
          .widget<TextButton>(find.byKey(const ValueKey('connection-action')));
      final disabled = entry.$1 == VpnStatus.connecting ||
          entry.$1 == VpnStatus.disconnecting;
      expect(button.onPressed == null, disabled);
      expect(find.text(entry.$3), findsWidgets);
      final controlSize =
          tester.getSize(find.byKey(const ValueKey('connection-action')));
      expect(controlSize, const Size(180, 180));
      await tester.tap(find.byKey(const ValueKey('connection-action')));
      await tester.tap(find.byKey(const ValueKey('logout')));
      expect(toggles, disabled ? 0 : 1);
      expect(logouts, disabled ? 0 : 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('normal compact action labels stay inside the circle',
      (tester) async {
    await size(tester, const Size(320, 480));
    for (final state in VpnStatus.values) {
      await tester.pumpWidget(fixtureHost(homeFixture(status: state)));
      final action = find.byKey(const ValueKey('connection-action'));
      final label = find.descendant(of: action, matching: find.byType(Text));
      expect(label, findsOneWidget);
      expect(tester.getSize(action), const Size(160, 160));
      final bounds = tester.getRect(action);
      final text = tester.getRect(label);
      expect(bounds.contains(text.topLeft), isTrue);
      expect(bounds.contains(text.bottomRight), isTrue);
    }
  });

  testWidgets('keyboard focus activates circle with Enter and Space',
      (tester) async {
    await size(tester, const Size(900, 680));
    var calls = 0;
    await tester.pumpWidget(fixtureHost(homeFixture(onToggle: () => calls++)));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final button = tester
        .widget<TextButton>(find.byKey(const ValueKey('connection-action')));
    expect(button.statesController!.value, contains(WidgetState.focused));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(calls, 2);
  });

  testWidgets('transition disables an already focused action and logout',
      (tester) async {
    await size(tester, const Size(900, 680));
    var calls = 0;
    await tester.pumpWidget(fixtureHost(homeFixture(onToggle: () => calls++)));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pumpWidget(fixtureHost(homeFixture(
        status: VpnStatus.connecting,
        onToggle: () => calls++,
        onLogout: () => calls++)));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, 0);
    expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('logout')))
            .onPressed,
        isNull);
  });

  testWidgets('animation never changes state or invokes actions',
      (tester) async {
    await size(tester, const Size(900, 680));
    var calls = 0;
    await tester.pumpWidget(fixtureHost(
        homeFixture(status: VpnStatus.connecting, onToggle: () => calls++),
        reducedMotion: false));
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('Connected'), findsNothing);
    expect(calls, 0);
    await tester.pumpWidget(fixtureHost(
        homeFixture(status: VpnStatus.connecting),
        reducedMotion: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('unavailable counters stay distinct from genuine zero',
      (tester) async {
    await size(tester, const Size(900, 680));
    await tester.pumpWidget(fixtureHost(homeFixture(available: false)));
    expect(find.text('Unavailable'), findsNWidgets(2));
    expect(find.text('0 B'), findsNothing);
    await tester.pumpWidget(fixtureHost(homeFixture()));
    expect(find.text('0 B'), findsNWidgets(2));
    await tester.pumpWidget(fixtureHost(
        homeFixture(available: false, status: VpnStatus.connecting)));
    expect(find.text('Pending'), findsNWidgets(2));
  });

  testWidgets('server labels have product semantics and no selector',
      (tester) async {
    await size(tester, const Size(900, 680));
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(fixtureHost(homeFixture(server: 'Germany')));
    expect(find.text('Germany'), findsOneWidget);
    expect(find.bySemanticsLabel('Server label: Germany. SecureWave Network.'),
        findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
    await tester.pumpWidget(fixtureHost(homeFixture(server: '\n\u0000')));
    expect(find.text('SecureWave Network'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('status is a live region, transfer values are not',
      (tester) async {
    await size(tester, const Size(900, 680));
    await tester.pumpWidget(fixtureHost(homeFixture()));
    final region =
        tester.widget<Semantics>(find.byKey(const ValueKey('vpn-state')));
    expect(region.properties.liveRegion, isTrue);
    final liveRegions = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((item) => item.properties.liveRegion == true);
    expect(liveRegions.length, 1);
  });

  test('unknown native output cannot leak into presentation', () {
    const raw = 'PrivateKey=secret; stack trace; HTTP internal payload';
    expect(safeVpnMessage(raw, canDisconnect: false),
        'SecureWave couldn’t establish the VPN connection.');
    expect(safeVpnMessage(raw, canDisconnect: true),
        'SecureWave couldn’t complete disconnection.');
    expect(
        safeVpnMessage('WireGuard has no recent peer handshake.',
            canDisconnect: false),
        'The VPN connection could not be verified.');
  });

  testWidgets(
      'existing auth fields retain values and validation on mode switch',
      (tester) async {
    await size(tester, const Size(900, 680));
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const SecureWaveApp());
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField).at(0), 'retained@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'short');
    await tester.tap(find.text('Already have an account? Sign in'));
    await tester.pumpAndSettle();
    final fields =
        tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
    expect(fields.length, 2);
    expect(fields[0].controller!.text, 'retained@example.com');
    expect(fields[1].controller!.text, 'short');
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.pump();
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
  });

  testWidgets('auth busy controls cannot submit or switch mode',
      (tester) async {
    await size(tester, const Size(900, 680));
    var calls = 0;
    await tester.pumpWidget(fixtureHost(AuthFixture(
        busy: true, onSubmit: () => calls++, onSwitch: () => calls++)));
    await tester.tap(find.byKey(const ValueKey('auth-submit')));
    await tester.tap(find.text('New to SecureWave? Create an account'));
    expect(calls, 0);
  });

  for (final viewport in [
    const Size(900, 680),
    const Size(1280, 720),
    const Size(640, 480),
    const Size(390, 844),
    const Size(320, 480),
  ]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('layout ${viewport.width}×${viewport.height}, scale $scale',
          (tester) async {
        await size(tester, viewport);
        for (final page in [
          homeFixture(status: VpnStatus.disconnecting, available: false),
          homeFixture(status: VpnStatus.error, error: 'unknown native output'),
          const AuthFixture(registering: true, validation: true),
        ]) {
          await tester.pumpWidget(fixtureHost(page, scale: scale));
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('compact enlarged layout keeps action and transfer reachable',
      (tester) async {
    await size(tester, const Size(320, 480));
    await tester.pumpWidget(
        fixtureHost(homeFixture(status: VpnStatus.connected), scale: 2));
    await tester.ensureVisible(find.byKey(const ValueKey('connection-action')));
    await tester.pump();
    final action =
        tester.getRect(find.byKey(const ValueKey('connection-action')));
    expect(action.top, greaterThanOrEqualTo(0));
    expect(action.bottom, lessThanOrEqualTo(480));
    await tester.ensureVisible(find.text('Upload'));
    await tester.pump();
    expect(tester.getRect(find.text('Upload')).bottom, lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'email Enter advances focus; final Enter uses original validation',
      (tester) async {
    await size(tester, const Size(900, 680));
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const SecureWaveApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Already have an account? Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextFormField).first);
    await tester.enterText(
        find.byType(TextFormField).first, 'person@example.com');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    final password =
        tester.widget<EditableText>(find.byType(EditableText).last);
    expect(password.focusNode.hasFocus, isTrue);
    await tester.enterText(find.byType(TextFormField).last, 'short');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    expect(find.text('Signing in…'), findsNothing);
  });

  test('approved readable colors meet contrast requirements', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
    }

    for (final background in [
      AppTheme.surfacePrimary,
      AppTheme.surfaceInteractive,
      AppTheme.stateSurface(AppTheme.connected, alpha: .16),
      AppTheme.stateSurface(AppTheme.error, alpha: .16)
    ]) {
      for (final foreground in [
        AppTheme.textPrimary,
        AppTheme.textSecondary,
        AppTheme.textMuted
      ]) {
        expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
      }
      expect(contrast(AppTheme.focusRing, background), greaterThanOrEqualTo(3));
    }
  });
}

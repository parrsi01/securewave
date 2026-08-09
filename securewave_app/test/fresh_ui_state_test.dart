import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/app.dart';
import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/services/secure_storage.dart';

class _TestSecureStorage extends SecureStorage {
  @override
  Future<String?> getAccessToken() async => null;

  @override
  Future<void> saveToken(String accessToken) async {}

  @override
  Future<void> clearToken() async {}

  @override
  Future<void> clearVpnRuntimeState() async {}
}

class _AuthenticatedTestSession extends AuthSession {
  _AuthenticatedTestSession() : super(storage: _TestSecureStorage());

  @override
  bool get isInitialized => true;

  @override
  bool get isAuthenticated => true;

  @override
  String? get accessToken => null;
}

void main() {
  testWidgets('mobile shell exposes exactly three semantic destinations',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpAuthenticatedShell(tester, const Size(390, 844));

    final navigationFinder = find.byKey(const ValueKey('mobile-navigation'));
    expect(navigationFinder, findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-navigation')), findsNothing);

    var navigation = tester.widget<NavigationBar>(navigationFinder);
    expect(navigation.destinations, hasLength(3));
    expect(navigation.selectedIndex, 0);
    _expectDestinationLabels(navigationFinder);
    expect(
      find.descendant(of: navigationFinder, matching: find.text('Account')),
      findsNothing,
    );

    for (final label in const ['Connect', 'Servers', 'Settings']) {
      final semanticsWidget = tester.widget<Semantics>(
        find.byKey(ValueKey(
          'mobile-nav-${label.toLowerCase()}-${label == 'Connect' ? 'selected' : 'unselected'}',
        )),
      );
      expect(
        semanticsWidget.properties.label,
        '$label navigation destination',
      );
    }

    await tester.tap(
      find.descendant(of: navigationFinder, matching: find.text('Servers')),
    );
    await tester.pumpAndSettle();

    navigation = tester.widget<NavigationBar>(navigationFinder);
    expect(navigation.selectedIndex, 1);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('mobile-nav-servers-selected')),
          )
          .properties
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop shell exposes three focused top destinations',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpAuthenticatedShell(tester, const Size(1280, 800));

    final navigationFinder = find.byKey(const ValueKey('desktop-navigation'));
    expect(navigationFinder, findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    _expectDestinationLabels(navigationFinder);
    expect(find.byKey(const ValueKey('desktop-nav-account')), findsNothing);

    for (final label in const ['Connect', 'Servers', 'Settings']) {
      final semanticsWidget = tester.widget<Semantics>(
        find.byKey(ValueKey('desktop-nav-${label.toLowerCase()}')),
      );
      expect(
        semanticsWidget.properties.label,
        '$label navigation destination',
      );
      expect(semanticsWidget.properties.button, isTrue);
    }

    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('desktop-nav-connect')),
          )
          .properties
          .selected,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('desktop-nav-settings')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('desktop-nav-settings')),
          )
          .properties
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('authenticated shell has no layout exceptions at target sizes',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in const [
      Size(390, 844),
      Size(760, 900),
      Size(1280, 800),
      Size(1440, 900),
    ]) {
      await _pumpAuthenticatedShell(tester, size);
      expect(
        tester.takeException(),
        isNull,
        reason: 'Connect layout failed at ${size.width}x${size.height}',
      );

      for (final destination in const ['Servers', 'Settings']) {
        if (size.width < 760) {
          final navigationFinder =
              find.byKey(const ValueKey('mobile-navigation'));
          await tester.tap(
            find.descendant(
              of: navigationFinder,
              matching: find.text(destination),
            ),
          );
        } else {
          await tester.tap(
            find.byKey(
              ValueKey('desktop-nav-${destination.toLowerCase()}'),
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$destination layout failed at ${size.width}x${size.height}',
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}

Future<void> _pumpAuthenticatedShell(
  WidgetTester tester,
  Size size,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  final session = _AuthenticatedTestSession();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWith(
          (_) => const AppConfig(
            apiBaseUrl: 'https://network-must-not-run.invalid/api',
            demoMode: true,
          ),
        ),
        authSessionProvider.overrideWith((_) => session),
      ],
      child: const SecureWaveApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectDestinationLabels(Finder navigationFinder) {
  for (final label in const ['Connect', 'Servers', 'Settings']) {
    expect(
      find.descendant(of: navigationFinder, matching: find.text(label)),
      findsOneWidget,
    );
  }
}

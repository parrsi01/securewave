import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/app.dart';
import 'package:securewave_app/core/config/app_config.dart';

void main() {
  testWidgets(
      'demo UI completes register, connect, disconnect, reconnect, and logout',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWith(
            (_) => const AppConfig(
              apiBaseUrl: 'https://network-must-not-run.invalid/api',
              demoMode: true,
            ),
          ),
        ],
        child: const SecureWaveApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DEMO MODE · Simulated connection only'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.tap(find.text('Create a new account'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField).at(0), 'reviewer@example.invalid');
    await tester.enterText(find.byType(TextFormField).at(1), 'Secure123');
    await tester.enterText(find.byType(TextFormField).at(2), 'Secure123');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('A deterministic simulated WireGuard experience.'),
        findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);

    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.text('Connecting'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('12.0 KB transferred'), findsOneWidget);

    await tester.tap(find.text('Disconnect'));
    await tester.pump();
    expect(find.text('Disconnecting'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pump();
    expect(find.text('Disconnected'), findsOneWidget);

    await tester.tap(find.text('Connect'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('12.0 KB transferred'), findsOneWidget);

    await tester.tap(find.text('Disconnect'));
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pump();
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('DEMO MODE · Simulated connection only'), findsOneWidget);
  });
}

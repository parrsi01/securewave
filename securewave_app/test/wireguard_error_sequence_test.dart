import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/app.dart';
import 'package:securewave_app/core/diagnostics/wireguard_error_catalog.dart';

void main() {
  test('WireGuard frontend catalog has unique, actionable cases', () {
    expect(wireGuardFrontendErrorCatalog.length, greaterThan(10));
    expect(
      wireGuardFrontendErrorCatalog.map((item) => item.id).toSet().length,
      wireGuardFrontendErrorCatalog.length,
    );
    for (final item in wireGuardFrontendErrorCatalog) {
      expect(item.code, isNotEmpty);
      expect(item.message, isNotEmpty);
    }
  });

  testWidgets('WireGuard frontend messages appear in order without VPN calls',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 900,
            child: WireGuardErrorSequence(
              interval: Duration(milliseconds: 10),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('1/'), findsOneWidget);
    expect(
        find.text(wireGuardFrontendErrorCatalog.first.message), findsOneWidget);
    expect(
      find.text(wireGuardFrontendErrorCatalog[1].message),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 11));
    expect(find.textContaining('2/'), findsOneWidget);
    expect(
      find.text(wireGuardFrontendErrorCatalog[1].message),
      findsOneWidget,
    );

    for (var index = 2;
        index <= wireGuardFrontendErrorCatalog.length;
        index++) {
      await tester.pump(const Duration(milliseconds: 11));
    }
    expect(
      find.textContaining(
        '${wireGuardFrontendErrorCatalog.length}/${wireGuardFrontendErrorCatalog.length}',
      ),
      findsOneWidget,
    );
    expect(
      find.text(wireGuardFrontendErrorCatalog.last.message),
      findsOneWidget,
    );
  });
}

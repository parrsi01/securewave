import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/server_region.dart';
import 'package:securewave_app/screens/locations/widgets/server_tile.dart';

void main() {
  testWidgets('premium server tile renders disabled reason for free users',
      (tester) async {
    var tapped = false;
    final server = ServerRegion.fromJson(<String, dynamic>{
      'server_id': 'premium-fra-1',
      'location': 'Frankfurt',
      'city': 'Frankfurt',
      'country': 'Germany',
      'tier_restriction': 'premium',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ServerTile(
            server: server,
            isSelected: false,
            isFavorite: false,
            enabled: false,
            disabledReason: 'Premium required',
            onTap: () => tapped = true,
            onToggleFavorite: () {},
          ),
        ),
      ),
    );

    expect(find.text('Premium'), findsOneWidget);
    expect(find.text('Premium required'), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    await tester.pump();
    expect(tapped, isFalse);
  });
}

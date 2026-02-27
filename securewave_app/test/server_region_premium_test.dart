import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/server_region.dart';

void main() {
  test('parses premium markers from server payload', () {
    final region = ServerRegion.fromJson(<String, dynamic>{
      'server_id': 'us-east-1',
      'location': 'New York',
      'city': 'New York',
      'country': 'United States',
      'tier_restriction': 'premium',
    });

    expect(region.tierRestriction, 'premium');
    expect(region.premiumOnly, isTrue);
  });
}

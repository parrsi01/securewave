import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/screens/settings/manage_devices_screen.dart';
import 'package:securewave_app/services/api_client.dart';

AppConfig _testConfig() => AppConfig(
      apiBaseUrl: 'http://localhost:8000',
      portalUrl: 'http://localhost:8000',
      upgradeUrl: 'http://localhost:8000',
      resetSessionOnBoot: false,
    );

Dio _stubDio(Map<String, dynamic> Function(RequestOptions) resolver) {
  final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final payload = resolver(options);
        handler.resolve(
          Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: payload,
          ),
        );
      },
    ),
  );
  return dio;
}

ApiClient _buildClient({
  List<Map<String, dynamic>> devices = const [],
  int total = 0,
  int limit = 1,
  int remaining = 1,
}) {
  return ApiClient(
    _testConfig(),
    dio: _stubDio((options) {
      if (options.path == '/vpn/devices') {
        return <String, dynamic>{
          'devices': devices,
          'total': total,
          'limit': limit,
          'remaining': remaining,
        };
      }
      return <String, dynamic>{};
    }),
  );
}

Widget _buildTestApp(ApiClient client) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(client),
    ],
    child: const MaterialApp(
      home: ManageDevicesScreen(),
    ),
  );
}

void main() {
  testWidgets('ManageDevicesScreen shows device list', (tester) async {
    final client = _buildClient(
      devices: [
        {
          'id': 1,
          'name': 'test-linux',
          'device_type': 'linux',
          'ip_address': '10.8.0.2',
          'server_location': 'Frankfurt',
          'is_active': true,
          'created_at': '2026-02-28T12:00:00Z',
        },
      ],
      total: 1,
      limit: 3,
      remaining: 2,
    );
    await tester.pumpWidget(_buildTestApp(client));
    await tester.pumpAndSettle();

    expect(find.text('test-linux'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('Frankfurt · 10.8.0.2'), findsOneWidget);
  });

  testWidgets('ManageDevicesScreen shows empty state', (tester) async {
    final client = _buildClient(total: 0, limit: 1, remaining: 1);
    await tester.pumpWidget(_buildTestApp(client));
    await tester.pumpAndSettle();

    expect(find.text('No active devices'), findsOneWidget);
    expect(find.text('0 / 1'), findsOneWidget);
  });

  testWidgets('ManageDevicesScreen shows quota bar at limit', (tester) async {
    final client = _buildClient(
      devices: [
        {
          'id': 1,
          'name': 'my-phone',
          'device_type': 'android',
          'ip_address': '10.8.0.3',
          'is_active': true,
          'created_at': '2026-02-28T12:00:00Z',
        },
      ],
      total: 1,
      limit: 1,
      remaining: 0,
    );
    await tester.pumpWidget(_buildTestApp(client));
    await tester.pumpAndSettle();

    expect(find.text('1 / 1'), findsOneWidget);
  });

  testWidgets('ManageDevicesScreen delete shows confirmation dialog',
      (tester) async {
    final client = _buildClient(
      devices: [
        {
          'id': 1,
          'name': 'my-phone',
          'device_type': 'android',
          'ip_address': '10.8.0.3',
          'is_active': true,
          'created_at': '2026-02-28T12:00:00Z',
        },
      ],
      total: 1,
      limit: 1,
      remaining: 0,
    );
    await tester.pumpWidget(_buildTestApp(client));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Remove Device'), findsOneWidget);
    expect(find.textContaining('my-phone'), findsWidgets);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
  });

  testWidgets('ManageDevicesScreen cancel dialog keeps device visible',
      (tester) async {
    final client = _buildClient(
      devices: [
        {
          'id': 1,
          'name': 'my-device',
          'device_type': 'windows',
          'ip_address': '10.8.0.4',
          'is_active': true,
          'created_at': '2026-02-28T12:00:00Z',
        },
      ],
      total: 1,
      limit: 3,
      remaining: 2,
    );
    await tester.pumpWidget(_buildTestApp(client));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('my-device'), findsOneWidget);
  });
}

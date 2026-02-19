import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/screens/home/widgets/connection_ring.dart';

/// A VpnService that reports a fixed initial status.
class _FixedStatusVpnService implements VpnService {
  _FixedStatusVpnService(this._status);

  final VpnStatus _status;

  @override
  bool get isNativeAvailable => false;

  @override
  String? get availabilityMessage => null;

  @override
  Future<VpnCapabilities> getCapabilities() async => VpnCapabilities.none;

  @override
  VpnStatus getStatus() => _status;

  @override
  Future<VpnStatus> connect(
      {required VpnProtocol protocol, Map<String, dynamic>? profile}) async {
    return _status;
  }

  @override
  Future<VpnStatus> disconnect() async => VpnStatus.disconnected;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String?> fakeStore;

  setUp(() {
    fakeStore = <String, String?>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        final args = methodCall.arguments is Map
            ? Map<String, dynamic>.from(methodCall.arguments as Map)
            : const <String, dynamic>{};
        final key = args['key']?.toString();
        switch (methodCall.method) {
          case 'read':
            return key == null ? null : fakeStore[key];
          case 'write':
            if (key != null) fakeStore[key] = args['value']?.toString();
            return null;
          case 'delete':
            if (key != null) fakeStore.remove(key);
            return null;
          case 'deleteAll':
            fakeStore.clear();
            return null;
          case 'readAll':
            return Map<String, String>.fromEntries(
              fakeStore.entries
                  .where((e) => e.value != null)
                  .map((e) => MapEntry(e.key, e.value!)),
            );
        }
        return null;
      },
    );
  });

  Widget buildWithService(VpnService service) {
    return ProviderScope(
      overrides: [vpnServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(
        home: Scaffold(body: Center(child: ConnectionRing())),
      ),
    );
  }

  group('ConnectionRing', () {
    testWidgets('shows "Tap to Connect" label when disconnected', (tester) async {
      await tester.pumpWidget(
        buildWithService(_FixedStatusVpnService(VpnStatus.disconnected)),
      );
      await tester.pump();

      expect(find.text('Tap to Connect'), findsOneWidget);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    });

    testWidgets('shows "Connected" label when connected', (tester) async {
      await tester.pumpWidget(
        buildWithService(_FixedStatusVpnService(VpnStatus.connected)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Connected'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('shows "Retry" label on error', (tester) async {
      await tester.pumpWidget(
        buildWithService(_FixedStatusVpnService(VpnStatus.error)),
      );
      await tester.pump();

      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('renders widget tree without errors', (tester) async {
      await tester.pumpWidget(
        buildWithService(_FixedStatusVpnService(VpnStatus.disconnected)),
      );
      await tester.pump();

      expect(find.byType(ConnectionRing), findsOneWidget);
      expect(find.byType(GestureDetector), findsWidgets);
    });
  });
}

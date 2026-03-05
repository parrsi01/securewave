import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/models/server_region.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
import 'package:securewave_app/screens/home/widgets/connection_ring.dart';
import 'package:securewave_app/screens/home/widgets/status_display.dart';

/// A VpnService that reports a fixed initial status.
class _FixedStatusVpnService implements VpnService {
  _FixedStatusVpnService(this._status);

  final VpnStatus _status;
  int connectCalls = 0;

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
    connectCalls += 1;
    return _status;
  }

  @override
  Future<VpnStatus> disconnect() async => VpnStatus.disconnected;
}

class _BannerVpnStateNotifier extends VpnStateNotifier {
  _BannerVpnStateNotifier(super.ref) {
    state = const VpnState(
      status: VpnStatus.connected,
      selectedServerId: 'fallback-1',
      failoverActive: true,
      failoverReason: 'failover_primary_down',
      failoverRegionId: 'fallback-1',
    );
  }
}

class _OptimizedVpnStateNotifier extends VpnStateNotifier {
  _OptimizedVpnStateNotifier(super.ref) {
    state = const VpnState(
      status: VpnStatus.connected,
      selectedServerId: 'na-1',
      failoverActive: false,
    );
  }
}

class _SelectedDownVpnStateNotifier extends VpnStateNotifier {
  _SelectedDownVpnStateNotifier(super.ref) {
    state = const VpnState(
      status: VpnStatus.disconnected,
      selectedServerId: 'down-selected',
    );
  }
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

  List<ServerRegion> serversFixture({required bool down}) {
    return <ServerRegion>[
      ServerRegion(
        id: 'test-1',
        name: 'Test Server',
        regionHealthStatus: down ? 'down' : 'up',
        regionHealthReasonCode: down ? 'host_unreachable' : null,
      ),
    ];
  }

  Widget buildWithService(
    VpnService service, {
    bool allServersDown = false,
    bool includeStatusDisplay = false,
  }) {
    final homeChild = includeStatusDisplay
        ? const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              ConnectionRing(),
              SizedBox(height: 16),
              StatusDisplay(),
            ],
          )
        : const Center(child: ConnectionRing());

    return ProviderScope(
      overrides: [
        vpnServiceProvider.overrideWithValue(service),
        serversProvider
            .overrideWith((ref) async => serversFixture(down: allServersDown)),
      ],
      child: MaterialApp(
        home: Scaffold(body: homeChild),
      ),
    );
  }

  group('ConnectionRing', () {
    testWidgets('shows "Connect" label when disconnected', (tester) async {
      await tester.pumpWidget(
        buildWithService(_FixedStatusVpnService(VpnStatus.disconnected)),
      );
      await tester.pump();

      expect(find.text('Connect'), findsOneWidget);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    });

    testWidgets('shows "Protected" label when connected', (tester) async {
      await tester.pumpWidget(
        buildWithService(_FixedStatusVpnService(VpnStatus.connected)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Protected'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('shows "Error" label on error', (tester) async {
      await tester.pumpWidget(
        buildWithService(_FixedStatusVpnService(VpnStatus.error)),
      );
      await tester.pump();

      expect(find.text('Error'), findsOneWidget);
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

    testWidgets('does not start connect when no servers are available',
        (tester) async {
      final service = _FixedStatusVpnService(VpnStatus.disconnected);
      await tester.pumpWidget(
        buildWithService(service, allServersDown: true),
      );
      await tester.pump();

      await tester.tap(find.byType(ConnectionRing));
      await tester.pump();

      expect(service.connectCalls, 0);
    });

    testWidgets(
        'does not start connect when selected region is down even if other regions are healthy',
        (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
      final service = _FixedStatusVpnService(VpnStatus.disconnected);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vpnServiceProvider.overrideWithValue(service),
            vpnStateProvider
                .overrideWith((ref) => _SelectedDownVpnStateNotifier(ref)),
            serversProvider.overrideWith(
              (ref) async => const <ServerRegion>[
                ServerRegion(
                  id: 'down-selected',
                  name: 'Selected Down',
                  regionHealthStatus: 'down',
                ),
                ServerRegion(
                  id: 'healthy-other',
                  name: 'Healthy Other',
                  regionHealthStatus: 'up',
                ),
              ],
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  ConnectionRing(),
                  SizedBox(height: 16),
                  StatusDisplay(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(ConnectionRing));
      await tester.pump();

      expect(service.connectCalls, 0);
      expect(find.text('Selected region is offline'), findsOneWidget);

      // The tap triggers an abandoned state machine connect attempt which
      // fires a zero-duration Dio timer for metrics snapshot. Drain it here
      // so the framework invariant check doesn't see a pending timer.
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets(
        'renders no servers available reason text when all servers down',
        (tester) async {
      await tester.pumpWidget(
        buildWithService(
          _FixedStatusVpnService(VpnStatus.disconnected),
          allServersDown: true,
          includeStatusDisplay: true,
        ),
      );
      await tester.pump();

      expect(find.text('No servers available'), findsOneWidget);
    });

    testWidgets('renders failover banner when connected via fallback region',
        (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vpnServiceProvider.overrideWithValue(
                _FixedStatusVpnService(VpnStatus.disconnected)),
            vpnStateProvider
                .overrideWith((ref) => _BannerVpnStateNotifier(ref)),
            serversProvider.overrideWith(
              (ref) async => const <ServerRegion>[
                ServerRegion(
                  id: 'fallback-1',
                  name: 'Frankfurt, Germany',
                  regionGroup: 'europe',
                  regionHealthStatus: 'up',
                ),
              ],
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: StatusDisplay()),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('Primary server unavailable. Connected via fallback region.'),
        findsOneWidget,
      );
      expect(
        find.text('Connected region: Frankfurt, Germany'),
        findsOneWidget,
      );
      expect(find.text('Using European fallback'), findsOneWidget);
    });

    testWidgets('renders Caribbean optimization label for North America route',
        (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vpnServiceProvider.overrideWithValue(
                _FixedStatusVpnService(VpnStatus.disconnected)),
            vpnStateProvider
                .overrideWith((ref) => _OptimizedVpnStateNotifier(ref)),
            serversProvider.overrideWith(
              (ref) async => const <ServerRegion>[
                ServerRegion(
                  id: 'na-1',
                  name: 'Ashburn, United States',
                  regionGroup: 'north_america',
                  regionHealthStatus: 'up',
                ),
              ],
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: StatusDisplay()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Optimized for Caribbean routing'), findsOneWidget);
    });
  });
}

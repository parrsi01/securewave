import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/config/app_config.dart';
import 'package:securewave_app/core/models/server_region.dart';
import 'package:securewave_app/core/models/vpn_profile.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/models/vpn_protocol_catalog.dart';
import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/services/auth_session.dart';
import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/app_state.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
import 'package:securewave_app/core/state/vpn_state_machine.dart';
import 'package:securewave_app/services/api_client.dart';

Map<String, String?> installSecureStorageMock({
  Map<String, String?>? initial,
}) {
  final store = <String, String?>{...(initial ?? const <String, String?>{})};
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
          return key == null ? null : store[key];
        case 'write':
          if (key != null) store[key] = args['value']?.toString();
          return null;
        case 'delete':
          if (key != null) store.remove(key);
          return null;
        case 'deleteAll':
          store.clear();
          return null;
        case 'readAll':
          return Map<String, String>.fromEntries(
            store.entries
                .where((entry) => entry.value != null)
                .map((entry) => MapEntry(entry.key, entry.value!)),
          );
      }
      return null;
    },
  );
  return store;
}

Future<void> waitForCondition(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      throw TimeoutException('Condition not reached within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> settleStateMachine({int turns = 20}) async {
  for (var i = 0; i < turns; i += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

AppConfig testAppConfig() {
  return AppConfig(
    apiBaseUrl: 'https://example.invalid',
    portalUrl: 'https://portal.example.invalid',
    upgradeUrl: 'https://upgrade.example.invalid',
    resetSessionOnBoot: false,
  );
}

ProviderContainer buildVpnContainer({
  required VpnService service,
  required ApiClient apiClient,
  VpnStateMachineConfig config = const VpnStateMachineConfig(),
  bool authenticated = true,
}) {
  final authSession =
      authenticated ? HarnessAuthenticatedSession() : AuthSession();
  return ProviderContainer(
    overrides: [
      appConfigProvider.overrideWith((ref) => testAppConfig()),
      vpnServiceProvider.overrideWithValue(service),
      apiClientProvider.overrideWithValue(apiClient),
      vpnStateMachineConfigProvider.overrideWithValue(config),
      authSessionProvider.overrideWith((ref) => authSession),
    ],
  );
}

class HarnessAuthenticatedSession extends AuthSession {
  HarnessAuthenticatedSession();

  @override
  bool get isAuthenticated => true;

  @override
  String? get accessToken => 'test-token';

  @override
  Future<void> get initializationComplete => Future<void>.value();

  @override
  bool hasFreshAccessToken({Duration minValidity = const Duration(seconds: 60)}) {
    return true;
  }

  @override
  String? accessTokenFreshnessIssue({
    Duration minValidity = const Duration(seconds: 60),
  }) {
    return null;
  }
}

class ControlledVpnService implements VpnService {
  ControlledVpnService({
    this.nativeAvailable = true,
    this.capabilities,
    this.connectDelay = Duration.zero,
    this.disconnectDelay = Duration.zero,
    this.connectError,
    this.disconnectError,
    this.connectGate,
    this.disconnectGate,
  });

  final bool nativeAvailable;
  final VpnCapabilities? capabilities;
  final Duration connectDelay;
  final Duration disconnectDelay;
  final Object? connectError;
  final Object? disconnectError;
  final Completer<void>? connectGate;
  final Completer<void>? disconnectGate;

  VpnStatus _status = VpnStatus.disconnected;
  int connectCalls = 0;
  int disconnectCalls = 0;
  VpnProtocol? lastConnectProtocol;
  Map<String, dynamic>? lastProfile;

  @override
  bool get isNativeAvailable => nativeAvailable;

  @override
  String? get availabilityMessage => null;

  @override
  Future<VpnCapabilities> getCapabilities() async {
    return capabilities ??
        VpnCapabilities(
          wireGuard: nativeAvailable,
          openVpn: false,
          ikev2: false,
          windowsThreadSafe: true,
          androidVpnServiceBased: true,
          macosEntitlementReady: true,
          linuxWireGuardInstalled: nativeAvailable,
        );
  }

  @override
  Future<VpnStatus> connect({
    required VpnProtocol protocol,
    Map<String, dynamic>? profile,
  }) async {
    connectCalls += 1;
    lastConnectProtocol = protocol;
    lastProfile = profile;
    if (_status == VpnStatus.connected || _status == VpnStatus.connecting) {
      return _status;
    }
    _status = VpnStatus.connecting;
    if (connectGate != null) {
      await connectGate!.future;
    }
    if (connectDelay > Duration.zero) {
      await Future<void>.delayed(connectDelay);
    }
    if (connectError != null) {
      _status = VpnStatus.error;
      if (connectError is Exception) throw connectError!;
      throw Exception(connectError.toString());
    }
    _status = VpnStatus.connected;
    return _status;
  }

  @override
  Future<VpnStatus> disconnect() async {
    disconnectCalls += 1;
    if (_status == VpnStatus.disconnected ||
        _status == VpnStatus.disconnecting) {
      return _status;
    }
    _status = VpnStatus.disconnecting;
    if (disconnectGate != null) {
      await disconnectGate!.future;
    }
    if (disconnectDelay > Duration.zero) {
      await Future<void>.delayed(disconnectDelay);
    }
    if (disconnectError != null) {
      _status = VpnStatus.error;
      if (disconnectError is Exception) throw disconnectError!;
      throw Exception(disconnectError.toString());
    }
    _status = VpnStatus.disconnected;
    return _status;
  }

  @override
  VpnStatus getStatus() => _status;
}

class FakeApiClient extends ApiClient {
  FakeApiClient({
    required AppConfig config,
    this.shouldFailProfile = false,
    this.shouldFailHealth = false,
    this.shouldFailServers = false,
    this.profileDelay = Duration.zero,
    this.profileError,
    this.profileConfig,
    this.metricsSnapshot = const <String, dynamic>{},
    this.servers,
    this.protocolCatalog,
  }) : super(config, dio: Dio(BaseOptions(baseUrl: config.apiBaseUrl)));

  final bool shouldFailProfile;
  final bool shouldFailHealth;
  final bool shouldFailServers;
  final Duration profileDelay;
  final Object? profileError;
  final String? profileConfig;
  final Map<String, dynamic> metricsSnapshot;
  final List<ServerRegion>? servers;
  final VpnProtocolCatalog? protocolCatalog;

  int profileFetchCalls = 0;
  int notifyConnectedCalls = 0;
  int notifyDisconnectedCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchHealth({CancelToken? cancelToken}) async {
    if (shouldFailHealth) {
      throw DioException(
        requestOptions: RequestOptions(path: '/health'),
        type: DioExceptionType.connectionError,
        error: 'connection_error',
      );
    }
    return const <String, dynamic>{'status': 'ok'};
  }

  @override
  Future<List<ServerRegion>> fetchServers({bool forceRefresh = false}) async {
    if (shouldFailServers) {
      throw DioException(
        requestOptions: RequestOptions(path: '/vpn/regions'),
        type: DioExceptionType.connectionError,
        error: 'connection_error',
      );
    }
    return servers ??
        const <ServerRegion>[
          ServerRegion(
            id: 'us-chi',
            name: 'US Chicago',
            city: 'Chicago',
            country: 'United States',
            countryCode: 'US',
            regionHealthStatus: 'healthy',
            healthStatus: 'healthy',
            supportedProtocols: <String>['wireguard'],
          ),
        ];
  }

  @override
  Future<VpnProtocolCatalog> fetchVpnProtocols({
    required String deviceType,
    CancelToken? cancelToken,
  }) async {
    return protocolCatalog ??
        VpnProtocolCatalog.fromJson({
          'user_tier': 'free',
          'device_type': deviceType,
          'protocols': [
            {
              'protocol': 'wireguard',
              'enabled': true,
              'server_enabled': true,
              'plan_enabled': true,
              'platform_supported': true,
            },
            {
              'protocol': 'openvpn',
              'enabled': true,
              'server_enabled': true,
              'plan_enabled': true,
              'platform_supported': true,
            },
            {
              'protocol': 'ikev2',
              'enabled': true,
              'server_enabled': true,
              'plan_enabled': true,
              'platform_supported': true,
            },
          ],
        });
  }

  @override
  Future<VpnProfile> fetchVpnProfile({
    int? deviceId,
    required String deviceName,
    required String deviceType,
    required VpnProtocol protocol,
    String? serverId,
    bool forceRotateKeys = false,
    CancelToken? cancelToken,
  }) async {
    profileFetchCalls += 1;
    final options = RequestOptions(path: '/vpn/profile');
    if (profileDelay > Duration.zero) {
      final deadline = DateTime.now().add(profileDelay);
      while (DateTime.now().isBefore(deadline)) {
        if (cancelToken?.isCancelled ?? false) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            message: 'cancelled',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
    if (shouldFailProfile) {
      if (profileError != null) {
        if (profileError is Exception) throw profileError!;
        throw Exception(profileError.toString());
      }
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: 'connection_error',
      );
    }
    final wgCfg = profileConfig ??
        '''
[Interface]
PrivateKey = TEST_PRIVATE_KEY
Address = 10.10.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = TEST_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0
Endpoint = 198.51.100.10:51820
''';

    Map<String, dynamic>? protocolProfile;
    String? wireguardConfig;
    if (protocol == VpnProtocol.openVpn) {
      protocolProfile = <String, dynamic>{
        'type': 'openvpn',
        'ovpn_config': '''
client
dev tun
proto udp
remote 198.51.100.10 1194
auth-user-pass
''',
        'username': 'test-openvpn-user',
        'password': 'test-openvpn-pass',
      };
    } else if (protocol == VpnProtocol.ikev2) {
      protocolProfile = <String, dynamic>{
        'type': 'ikev2',
        'auth_method': 'eap-mschapv2',
        'server': '198.51.100.10',
        'username': 'test-ikev2-user',
        'password': 'test-ikev2-pass',
      };
    } else {
      wireguardConfig = wgCfg;
    }

    return VpnProfile.fromJson({
      'device_id': (deviceId ?? 0) > 0 ? deviceId : 123,
      'device_name': deviceName,
      'device_type': deviceType,
      'protocol': vpnProtocolStorageValue(protocol),
      'server_id': serverId ?? 'us-chi',
      'server_location': 'Chicago',
      if (wireguardConfig != null) 'wireguard_config': wireguardConfig,
      if (protocolProfile != null) 'profile': protocolProfile,
      'peer_registered': true,
      'registration_status': 'ok',
      'dns': {
        'servers': ['1.1.1.1'],
      },
      'kill_switch': {
        'mode': 'enabled',
      },
    });
  }

  @override
  Future<void> notifyVpnConnected({
    String? region,
    String? serverId,
    VpnProtocol? protocol,
  }) async {
    notifyConnectedCalls += 1;
  }

  @override
  Future<void> notifyVpnDisconnected() async {
    notifyDisconnectedCalls += 1;
  }

  @override
  Future<Map<String, dynamic>?> fetchVpnMetricsSnapshot(
      {CancelToken? cancelToken}) async {
    return metricsSnapshot;
  }
}

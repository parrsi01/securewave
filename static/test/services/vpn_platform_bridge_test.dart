import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_protocol.dart';
import 'package:securewave_app/core/services/vpn_platform_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('securewave/vpn_platform_bridge');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('connect forwards selected protocol and profile payload', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return null;
    });

    final bridge = VpnPlatformBridge(channel: channel);
    await bridge.connect(
      protocol: VpnProtocol.ikev2,
      profile: const <String, Object?>{
        'server': '198.51.100.10',
        'username': 'demo-user',
      },
    );

    expect(captured, isNotNull);
    expect(captured!.method, 'connect');
    final args = Map<Object?, Object?>.from(captured!.arguments as Map);
    expect(args['protocol'], 'ikev2');
    expect(args['server'], '198.51.100.10');
    expect(args['username'], 'demo-user');
  });

  test('OpenVPN connect is blocked before native connect when runtime missing',
      () async {
    var diagnosticsCalls = 0;
    var connectCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'diagnostics') {
        diagnosticsCalls += 1;
        return <String, Object?>{
          'available': true,
          'extensionEmbedded': true,
          'appGroupConfigured': true,
          'tunnelManagerReady': true,
          'personalVpnReady': true,
          'protocolCapabilities': <String, Object?>{
            'wireguard': <String, Object?>{
              'supported': true,
              'runtimeAvailable': true,
            },
            'openvpn': <String, Object?>{
              'supported': true,
              'runtimeAvailable': false,
              'reason': 'Apple OpenVPN runtime not linked',
            },
            'ikev2': <String, Object?>{
              'supported': true,
              'runtimeAvailable': true,
            },
          },
          'openVpnRuntimeLinked': false,
          'openVpnInstallHint':
              'Replace SecureWavePlaceholderOpenVPNEngine with your licensed runtime.',
        };
      }
      if (call.method == 'connect') {
        connectCalls += 1;
      }
      return null;
    });

    final bridge = VpnPlatformBridge(channel: channel);
    await expectLater(
      () => bridge.connect(
        protocol: VpnProtocol.openVpn,
        profile: const <String, Object?>{
          'ovpn_config': 'client\nremote 198.51.100.10 1194',
        },
      ),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          openVpnRuntimeNotLinkedErrorCode,
        ),
      ),
    );

    expect(diagnosticsCalls, 1);
    expect(connectCalls, 0);
  });

  test('parses Apple diagnostics protocol flags', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'diagnostics') {
        return <String, Object?>{
          'available': true,
          'extensionEmbedded': true,
          'appGroupConfigured': true,
          'tunnelManagerReady': true,
          'personalVpnReady': true,
          'supportedProtocols': <String, Object?>{
            'wireguard': true,
            'openvpn': true,
            'ikev2': true,
          },
          'protocolCapabilities': <String, Object?>{
            'wireguard': <String, Object?>{
              'supported': true,
              'runtimeAvailable': true,
            },
            'openvpn': <String, Object?>{
              'supported': true,
              'runtimeAvailable': false,
              'reason': 'Apple OpenVPN runtime not linked',
            },
            'ikev2': <String, Object?>{
              'supported': true,
              'runtimeAvailable': true,
            },
          },
          'openVpnRuntimeLinked': false,
          'openVpnInstallHint':
              'Replace SecureWavePlaceholderOpenVPNEngine with your licensed runtime.',
          'activeProtocol': 'ikev2',
          'configuredProtocol': 'wireguard',
        };
      }
      return null;
    });

    final bridge = VpnPlatformBridge(channel: channel);
    final diagnostics = await bridge.diagnostics();

    expect(diagnostics.available, isTrue);
    expect(diagnostics.wireGuardSupported, isTrue);
    expect(diagnostics.openVpnSupported, isTrue);
    expect(diagnostics.ikev2Supported, isTrue);
    expect(diagnostics.openVpnRuntimeAvailable, isFalse);
    expect(diagnostics.openVpnCapability.reason,
        'Apple OpenVPN runtime not linked');
    expect(diagnostics.personalVpnReady, isTrue);
    expect(diagnostics.openVpnRuntimeLinked, isFalse);
    expect(diagnostics.openVpnInstallHint, contains('licensed runtime'));
    expect(diagnostics.activeProtocol, 'ikev2');
    expect(diagnostics.configuredProtocol, 'wireguard');
  });

  test('parses Apple status protocol metadata', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'status') {
        return <String, Object?>{
          'state': 'connected',
          'protocol': 'ikev2',
          'interface': 'ipsec',
          'rxBytes': 1024,
          'txBytes': 512,
        };
      }
      return null;
    });

    final bridge = VpnPlatformBridge(channel: channel);
    final status = await bridge.status();

    expect(status.state, VpnPlatformBridgeState.connected);
    expect(status.protocol, 'ikev2');
    expect(status.interfaceName, 'ipsec');
    expect(status.rxBytes, 1024);
    expect(status.txBytes, 512);
  });
}

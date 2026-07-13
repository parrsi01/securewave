import 'package:flutter_test/flutter_test.dart';
import 'package:securewave_app/core/models/server_region.dart';
import 'package:securewave_app/core/models/vpn_profile.dart';
import 'package:securewave_app/core/models/vpn_protocol.dart';

void main() {
  test('ServerRegion parses live protocol and health metadata', () {
    final region = ServerRegion.fromJson({
      'server_id': 'de-nue-1',
      'location': 'Nuremberg',
      'country': 'Germany',
      'latency_ms': 0.051,
      'load_percent': 12.4,
      'region_health_status': 'up',
      'supported_protocols': ['wireguard', 'openvpn', 'ikev2'],
      'premium_only': false,
    });

    expect(region.id, 'de-nue-1');
    expect(region.latencyMs, 0);
    expect(region.loadPercent, 12.4);
    expect(region.supportsProtocol('openvpn'), isTrue);
    expect(region.supportsProtocol('ikev2'), isTrue);
    expect(region.premiumOnly, isFalse);
  });

  test('ServerRegion falls back to backend protocol booleans', () {
    final region = ServerRegion.fromJson({
      'server_id': 'de-nue-1',
      'location': 'Nuremberg',
      'supports_wireguard': true,
      'supports_openvpn': true,
      'supports_ikev2': false,
    });

    expect(region.supportsProtocol('wireguard'), isTrue);
    expect(region.supportsProtocol('openvpn'), isTrue);
    expect(region.supportsProtocol('ikev2'), isFalse);
  });

  test('VpnProfile reads nested live OpenVPN profile payload', () {
    final profile = VpnProfile.fromJson({
      'device_id': 64,
      'device_name': 'Linux',
      'device_type': 'linux',
      'protocol': 'openvpn',
      'server_id': 'de-nue-1',
      'server_location': 'Nuremberg, Germany',
      'issued_at': '2026-05-24T17:51:06Z',
      'expires_at': '2026-05-24T18:51:06Z',
      'wireguard_config': null,
      'profile': {
        'type': 'openvpn',
        'ovpn_config': 'client\nremote 138.199.204.139 1194\n',
      },
      'dns': {
        'servers': ['94.140.14.14'],
      },
      'kill_switch': {
        'mode': 'disabled',
      },
      'peer_registered': true,
      'registration_status': 'openvpn_profile_issued',
    });

    expect(profile.configForProtocol(VpnProtocol.openVpn), contains('client'));
    expect(profile.configForProtocol(VpnProtocol.wireGuard), isEmpty);
  });

  test('VpnProfile converts nested live IKEv2 payload into runner config', () {
    final profile = VpnProfile.fromJson({
      'device_id': 65,
      'protocol': 'ikev2',
      'server_id': 'de-nue-1',
      'server_location': 'Nuremberg, Germany',
      'profile': {
        'type': 'ikev2',
        'server': '138.199.204.139',
        'remote_id': '138.199.204.139',
        'username': 'sw-ikev2-user',
        'password': 'temporary-profile-secret',
        'ca_cert_pem':
            '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----',
      },
    });

    final config = profile.configForProtocol(VpnProtocol.ikev2);
    expect(config, contains('connections {'));
    expect(config, contains('remote_addrs = 138.199.204.139'));
    expect(config, contains('eap_id = "sw-ikev2-user"'));
    expect(config, contains('id = "138.199.204.139"'));
    expect(config, contains('secret = "temporary-profile-secret"'));
    expect(config, contains('# ca_cert_pem_begin'));
    expect(config, contains('# ca_cert_pem_end'));
  });

  test('VpnProfile quotes live IKEv2 swanctl credentials', () {
    final profile = VpnProfile.fromJson({
      'protocol': 'ikev2',
      'profile': {
        'type': 'ikev2',
        'server': 'vpn.example.test',
        'remote_id': 'vpn"edge.example.test',
        'username': r'user\name@example.test',
        'password': r'secret"with\slashes',
        'ca_cert_pem':
            '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----',
      },
    });

    final config = profile.configForProtocol(VpnProtocol.ikev2);
    expect(config, contains(r'eap_id = "user\\name@example.test"'));
    expect(config, contains(r'id = "vpn\"edge.example.test"'));
    expect(config, contains(r'secret = "secret\"with\\slashes"'));
  });

  test('VpnProfile rejects multiline IKEv2 scalar fields', () {
    final profile = VpnProfile.fromJson({
      'protocol': 'ikev2',
      'profile': {
        'type': 'ikev2',
        'server': 'vpn.example.test',
        'remote_id': 'vpn.example.test\nsecret = "injected"',
        'username': 'sw-ikev2-user',
        'password': 'temporary-profile-secret',
      },
    });

    expect(profile.configForProtocol(VpnProtocol.ikev2), isEmpty);
  });
}

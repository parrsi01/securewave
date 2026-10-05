import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api_service.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

class VpnServiceException implements Exception {
  const VpnServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VpnTrafficStats {
  const VpnTrafficStats({
    required this.rxBytes,
    required this.txBytes,
    required this.available,
  });

  final int rxBytes;
  final int txBytes;
  final bool available;

  factory VpnTrafficStats.fromMap(Map<Object?, Object?> values) {
    int bytes(Object? value) =>
        value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    final available = values['counters_available'] == true ||
        values['counters_available']?.toString().toLowerCase() == 'true';
    return VpnTrafficStats(
      rxBytes: bytes(values['rx_bytes']),
      txBytes: bytes(values['tx_bytes']),
      available: available,
    );
  }

  static const unavailable = VpnTrafficStats(
    rxBytes: 0,
    txBytes: 0,
    available: false,
  );
}

class WireGuardKeyPair {
  const WireGuardKeyPair({required this.privateKey, required this.publicKey});

  final String privateKey;
  final String publicKey;
}

class WireGuardRuntimeSnapshot {
  const WireGuardRuntimeSnapshot({
    required this.status,
    required this.interfaceName,
    required this.rxBytes,
    required this.txBytes,
    required this.countersAvailable,
    required this.peerLatestHandshakes,
  });

  final VpnStatus status;
  final String interfaceName;
  final int rxBytes;
  final int txBytes;
  final bool countersAvailable;
  final Map<String, int> peerLatestHandshakes;

  factory WireGuardRuntimeSnapshot.fromMap(Map<Object?, Object?>? values) {
    int? bytes(Object? value) {
      if (value is num && value >= 0 && value == value.toInt()) {
        return value.toInt();
      }
      return null;
    }

    final status = switch (values?['status']) {
      'connected' => VpnStatus.connected,
      'disconnected' => VpnStatus.disconnected,
      _ => null,
    };
    final interfaceName = values?['interface'];
    final rxBytes = bytes(values?['rx_bytes']);
    final txBytes = bytes(values?['tx_bytes']);
    final countersAvailable = values?['counters_available'];
    final rawHandshakes = values?['peer_handshakes'];
    if (status == null ||
        interfaceName != 'sw-wg' ||
        rxBytes == null ||
        txBytes == null ||
        countersAvailable is! bool ||
        rawHandshakes is! String ||
        (status == VpnStatus.connected && !countersAvailable) ||
        (status == VpnStatus.disconnected && countersAvailable)) {
      throw const VpnServiceException(
        'The Linux helper returned invalid WireGuard runtime status.',
      );
    }

    final handshakes = <String, int>{};
    for (final line in const LineSplitter().convert(rawHandshakes)) {
      if (line.trim().isEmpty) continue;
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length != 2 ||
          !RegExp(r'^[A-Za-z0-9+/]{43}=$').hasMatch(fields.first)) {
        throw const VpnServiceException(
          'The Linux helper returned invalid WireGuard peer status.',
        );
      }
      final timestamp = int.tryParse(fields[1]);
      if (timestamp == null ||
          timestamp < 0 ||
          handshakes.containsKey(fields.first)) {
        throw const VpnServiceException(
          'The Linux helper returned invalid WireGuard peer status.',
        );
      }
      handshakes[fields.first] = timestamp;
      if (handshakes.length > 1024) {
        throw const VpnServiceException(
          'The Linux helper returned too many WireGuard peers.',
        );
      }
    }

    return WireGuardRuntimeSnapshot(
      status: status,
      interfaceName: interfaceName as String,
      rxBytes: rxBytes,
      txBytes: txBytes,
      countersAvailable: countersAvailable,
      peerLatestHandshakes: Map.unmodifiable(handshakes),
    );
  }
}

class VpnService {
  static const _interfaceName = 'sw-wg';
  static const _channel = MethodChannel('securewave/vpn');

  VpnStatus _status = VpnStatus.disconnected;
  bool _available = false;
  String? _availabilityError;
  String? _statusError;

  VpnStatus get status => _status;
  String? get statusError => _statusError;

  Future<WireGuardKeyPair> generateKeyPair() async {
    try {
      final privateKey = await _runWg(['genkey']);
      return await keyPairFromPrivateKey(privateKey);
    } on ProcessException {
      throw const VpnServiceException(
        'WireGuard tools are not installed on this Linux system.',
      );
    }
  }

  Future<WireGuardKeyPair> keyPairFromPrivateKey(String privateKey) async {
    if (!_isKey(privateKey)) {
      throw const VpnServiceException(
        'The stored WireGuard private key is invalid.',
      );
    }
    final publicKey = await _runWg(['pubkey'], stdinText: privateKey);
    if (!_isKey(publicKey)) {
      throw const VpnServiceException(
        'WireGuard returned an invalid local keypair.',
      );
    }
    return WireGuardKeyPair(privateKey: privateKey, publicKey: publicKey);
  }

  Future<String> _runWg(List<String> arguments, {String? stdinText}) async {
    final process = await Process.start('wg', arguments);
    if (stdinText != null) process.stdin.write('$stdinText\n');
    await process.stdin.close();
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode;
    final output = (await stdout).trim();
    await stderr;
    if (exitCode != 0 || output.isEmpty) {
      throw const VpnServiceException('WireGuard key generation failed.');
    }
    return output;
  }

  bool _isKey(String value) => RegExp(r'^[A-Za-z0-9+/]{43}=$').hasMatch(value);

  Future<String> getPublicIp() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.https('api.ipify.org'));
      request.headers.set(HttpHeaders.acceptHeader, 'text/plain');
      final response = await request.close().timeout(
            const Duration(seconds: 10),
          );
      final address = (await response.transform(utf8.decoder).join()).trim();
      if (response.statusCode != HttpStatus.ok ||
          InternetAddress.tryParse(address) == null) {
        throw const VpnServiceException(
          'Could not verify internet connectivity and public egress.',
        );
      }
      return address;
    } on VpnServiceException {
      rethrow;
    } catch (_) {
      throw const VpnServiceException(
        'Could not verify internet connectivity and public egress.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<String> verifyConnection({
    required String previousPublicIp,
    required String expectedServerPublicKey,
  }) async {
    final runtime = await _getWireGuardRuntime();
    if (runtime.status != VpnStatus.connected ||
        runtime.interfaceName != 'sw-wg') {
      throw const VpnServiceException('WireGuard interface is not active.');
    }

    final handshakeTimestamp =
        runtime.peerLatestHandshakes[expectedServerPublicKey];
    if (handshakeTimestamp == null) {
      throw const VpnServiceException(
        'The expected WireGuard peer is not configured.',
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (handshakeTimestamp <= 0 ||
        handshakeTimestamp > now + 30 ||
        now - handshakeTimestamp > 180) {
      throw const VpnServiceException(
        'WireGuard has no recent peer handshake.',
      );
    }

    if (!runtime.countersAvailable ||
        runtime.rxBytes == 0 ||
        runtime.txBytes == 0) {
      throw const VpnServiceException(
        'WireGuard interface counters are unavailable.',
      );
    }

    final route = await Process.run('ip', ['-4', 'route', 'get', '1.1.1.1']);
    if (route.exitCode != 0 ||
        !(route.stdout as String).contains('dev $_interfaceName')) {
      throw const VpnServiceException('The VPN internet route is not active.');
    }

    final publicIp = await getPublicIp();
    if (publicIp == previousPublicIp) {
      throw const VpnServiceException('VPN egress did not change.');
    }
    final stats = await getTrafficStats();
    if (!stats.available || stats.rxBytes == 0 || stats.txBytes == 0) {
      throw const VpnServiceException(
        'WireGuard traffic counters are unavailable.',
      );
    }
    return publicIp;
  }

  Future<WireGuardRuntimeSnapshot> _getWireGuardRuntime() async {
    final runtime = await _channel.invokeMapMethod<Object?, Object?>(
      'getWireGuardRuntime',
    );
    return WireGuardRuntimeSnapshot.fromMap(runtime);
  }

  Future<void> verifyDisconnected({String? expectedPublicIp}) async {
    final status = await refreshRuntimeStatus();
    if (status != VpnStatus.disconnected) {
      throw const VpnServiceException('WireGuard interface is still active.');
    }
    if (expectedPublicIp != null && await getPublicIp() != expectedPublicIp) {
      throw const VpnServiceException(
        'Normal internet access was not restored after disconnect.',
      );
    }
  }

  Future<bool> refreshAvailability() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.linux) {
      _available = false;
      _availabilityError = 'SecureWave VPN is available on Linux only.';
      return false;
    }
    try {
      _available = await _channel.invokeMethod<bool>('isAvailable', const {
            'protocol': 'wireguard',
          }) ==
          true;
      _availabilityError = null;
    } on PlatformException catch (error) {
      _available = false;
      _availabilityError = error.message;
    } on MissingPluginException {
      _available = false;
      _availabilityError = 'The Linux WireGuard helper is unavailable.';
    }
    return _available;
  }

  Future<VpnStatus> connect(
    String config, {
    required UsageSession session,
    required String expectedPeer,
  }) async {
    if (_status == VpnStatus.connected ||
        _status == VpnStatus.connecting ||
        _status == VpnStatus.disconnecting) {
      return _status;
    }
    _status = VpnStatus.connecting;
    try {
      if (config.trim().isEmpty) {
        throw const VpnServiceException(
          'The API returned an empty WireGuard profile.',
        );
      }
      if (!await refreshAvailability()) {
        throw VpnServiceException(
          _availabilityError ?? 'The Linux WireGuard helper is unavailable.',
        );
      }
      await _channel.invokeMethod<void>('connect', {
        'protocol': 'wireguard',
        'config': config,
        'session_id': session.id.toString(),
        'reporting_token': session.token,
        'expected_peer': expectedPeer,
      });
      _status = VpnStatus.connected;
      return _status;
    } on PlatformException catch (error) {
      _status = VpnStatus.disconnected;
      throw VpnServiceException(
        error.message ?? 'Could not connect the WireGuard tunnel.',
      );
    } on MissingPluginException {
      _status = VpnStatus.disconnected;
      throw const VpnServiceException(
        'The Linux WireGuard helper is unavailable.',
      );
    } catch (_) {
      _status = VpnStatus.disconnected;
      rethrow;
    }
  }

  Future<VpnStatus> disconnect() async {
    if (_status == VpnStatus.disconnecting) return _status;
    _status = VpnStatus.disconnecting;
    try {
      if (!await refreshAvailability()) {
        throw VpnServiceException(
          _availabilityError ?? 'Could not reach the Linux WireGuard helper.',
        );
      }
      await _channel.invokeMethod<void>('disconnect');
      _status = VpnStatus.disconnected;
      return _status;
    } on PlatformException catch (error) {
      _status = VpnStatus.error;
      throw VpnServiceException(
        error.message ?? 'Could not disconnect the WireGuard tunnel.',
      );
    } on MissingPluginException {
      _status = VpnStatus.error;
      throw const VpnServiceException(
        'The Linux WireGuard helper is unavailable.',
      );
    } catch (_) {
      _status = VpnStatus.error;
      rethrow;
    }
  }

  Future<VpnStatus> refreshRuntimeStatus() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.linux) {
      _status = VpnStatus.disconnected;
      return _status;
    }
    try {
      final values = await _channel.invokeMapMethod<Object?, Object?>(
        'getStatus',
      );
      _statusError = values?['message']?.toString();
      _status = _statusError != null && _statusError!.isNotEmpty
          ? VpnStatus.error
          : switch (values?['status']?.toString()) {
              'connected' => VpnStatus.connected,
              _ => VpnStatus.disconnected,
            };
      return _status;
    } on PlatformException catch (error) {
      _statusError = error.message;
      _status = VpnStatus.error;
      return _status;
    } on MissingPluginException {
      _statusError = 'The Linux WireGuard helper is unavailable.';
      _status = VpnStatus.error;
      return _status;
    }
  }

  Future<VpnTrafficStats> getTrafficStats() async {
    if (!_available) return VpnTrafficStats.unavailable;
    try {
      final values = await _channel.invokeMapMethod<Object?, Object?>(
        'getTrafficStats',
        const {'protocol': 'wireguard'},
      );
      return values == null
          ? VpnTrafficStats.unavailable
          : VpnTrafficStats.fromMap(values);
    } on PlatformException {
      return VpnTrafficStats.unavailable;
    } on MissingPluginException {
      _available = false;
      return VpnTrafficStats.unavailable;
    }
  }

  Future<Map<Object?, Object?>> usageRecordingStatus() async =>
      await _channel.invokeMapMethod<Object?, Object?>(
        'getUsageRecordingStatus',
      ) ??
      {};

  Future<void> confirmUsage() => _channel.invokeMethod<void>('confirmUsage');
}

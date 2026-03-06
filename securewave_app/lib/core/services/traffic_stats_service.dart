import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:platform_info/platform_info.dart';

import '../logging/app_logger.dart';
import '../models/traffic_snapshot.dart';

final trafficStatsServiceProvider = Provider<TrafficStatsService>((ref) {
  return TrafficStatsService();
});

class TrafficStatsService {
  static const MethodChannel _channel =
      MethodChannel('securewave/traffic_stats');

  Future<TrafficSnapshot> sample({String? preferredInterface}) async {
    if (kIsWeb) {
      return TrafficSnapshot(
        receivedBytes: 0,
        transmittedBytes: 0,
        timestamp: DateTime.now(),
        countersAvailable: false,
        statusMessage: 'Traffic counters unavailable on web.',
      );
    }

    final os = platform.operatingSystem.name.toLowerCase();
    switch (os) {
      case 'linux':
        return _readLinuxProcNetDev(preferredInterface: preferredInterface);
      case 'macos':
      case 'ios':
      case 'windows':
      case 'android':
        return _readPlatformChannel();
      default:
        return TrafficSnapshot(
          receivedBytes: 0,
          transmittedBytes: 0,
          timestamp: DateTime.now(),
          countersAvailable: false,
          statusMessage: 'Traffic counters unavailable on this platform.',
        );
    }
  }

  Future<TrafficSnapshot> _readPlatformChannel() async {
    try {
      final response =
          await _channel.invokeMapMethod<String, dynamic>('getTrafficStats');
      final rxBytes = (response?['rxBytes'] as num?)?.toInt() ??
          (response?['receivedBytes'] as num?)?.toInt() ??
          0;
      final txBytes = (response?['txBytes'] as num?)?.toInt() ??
          (response?['transmittedBytes'] as num?)?.toInt() ??
          0;
      final interfaceName = response?['interfaceName']?.toString();
      final countersAvailable = response?['countersAvailable'] != false;
      final statusMessage = response?['details']?.toString();
      return TrafficSnapshot(
        receivedBytes: rxBytes,
        transmittedBytes: txBytes,
        timestamp: DateTime.now(),
        interfaceName: interfaceName == null || interfaceName.isEmpty
            ? null
            : interfaceName,
        countersAvailable: countersAvailable,
        statusMessage: statusMessage,
      );
    } on MissingPluginException {
      return TrafficSnapshot(
        receivedBytes: 0,
        transmittedBytes: 0,
        timestamp: DateTime.now(),
        countersAvailable: false,
        statusMessage: 'Native traffic counters unavailable.',
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Traffic stats unavailable from platform channel.',
        category: AppLogCategory.tunnel,
      );
      AppLogger.error(
        'Traffic stats channel error',
        error: error,
        stackTrace: stackTrace,
        category: AppLogCategory.tunnel,
      );
      return TrafficSnapshot(
        receivedBytes: 0,
        transmittedBytes: 0,
        timestamp: DateTime.now(),
        countersAvailable: false,
        statusMessage: 'Native traffic counters unavailable.',
      );
    }
  }

  Future<TrafficSnapshot> _readLinuxProcNetDev({
    String? preferredInterface,
  }) async {
    try {
      final content = await File('/proc/net/dev').readAsString();
      final lines = const LineSplitter().convert(content).skip(2);
      final statsByInterface = <String, TrafficSnapshot>{};

      for (final line in lines) {
        final normalized = line.trim();
        if (normalized.isEmpty || !normalized.contains(':')) {
          continue;
        }
        final parts = normalized.split(':');
        final interfaceName = parts.first.trim();
        final values = parts.last.trim().split(RegExp(r'\s+'));
        if (values.length < 9) {
          continue;
        }
        statsByInterface[interfaceName] = TrafficSnapshot(
          receivedBytes: int.tryParse(values[0]) ?? 0,
          transmittedBytes: int.tryParse(values[8]) ?? 0,
          timestamp: DateTime.now(),
          interfaceName: interfaceName,
        );
      }

      final activeInterface = _selectLinuxTunnelInterface(
        statsByInterface.keys.toList(growable: false),
        preferredInterface: preferredInterface,
      );
      if (activeInterface == null) {
        return TrafficSnapshot(
          receivedBytes: 0,
          transmittedBytes: 0,
          timestamp: DateTime.now(),
          countersAvailable: false,
          statusMessage: 'Native traffic counters unavailable.',
        );
      }

      final snapshot = statsByInterface[activeInterface];
      return TrafficSnapshot(
        receivedBytes: snapshot?.receivedBytes ?? 0,
        transmittedBytes: snapshot?.transmittedBytes ?? 0,
        timestamp: DateTime.now(),
        interfaceName: activeInterface,
        countersAvailable: true,
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Unable to read /proc/net/dev for traffic stats.',
        category: AppLogCategory.tunnel,
      );
      AppLogger.error(
        'Linux traffic stats error',
        error: error,
        stackTrace: stackTrace,
        category: AppLogCategory.tunnel,
      );
      return TrafficSnapshot(
        receivedBytes: 0,
        transmittedBytes: 0,
        timestamp: DateTime.now(),
        countersAvailable: false,
        statusMessage: 'Native traffic counters unavailable.',
      );
    }
  }

  String? _selectLinuxTunnelInterface(
    List<String> interfaces, {
    String? preferredInterface,
  }) {
    if (preferredInterface != null &&
        preferredInterface.isNotEmpty &&
        interfaces.contains(preferredInterface)) {
      return preferredInterface;
    }

    final defaultRoute = _readDefaultRouteInterface();
    if (defaultRoute != null && _isTunnelInterface(defaultRoute)) {
      return defaultRoute;
    }

    for (final interface in interfaces) {
      if (_isTunnelInterface(interface)) {
        return interface;
      }
    }
    return null;
  }

  bool _isTunnelInterface(String name) {
    return name.startsWith('wg') ||
        name.startsWith('tun') ||
        name.startsWith('utun') ||
        name.startsWith('sw-wg');
  }

  String? _readDefaultRouteInterface() {
    try {
      final lines = File('/proc/net/route').readAsLinesSync();
      for (final line in lines.skip(1)) {
        final columns = line.trim().split(RegExp(r'\s+'));
        if (columns.length >= 3 && columns[1] == '00000000') {
          return columns[0];
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

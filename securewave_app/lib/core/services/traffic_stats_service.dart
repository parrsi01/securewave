import 'dart:async';
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
  TrafficStatsService();

  static const MethodChannel _channel =
      MethodChannel('securewave/traffic_stats');

  Future<TrafficSnapshot> sample() async {
    if (kIsWeb) {
      return TrafficSnapshot(
        receivedBytes: 0,
        transmittedBytes: 0,
        timestamp: DateTime.now(),
      );
    }

    final os = platform.operatingSystem.name.toLowerCase();
    switch (os) {
      case 'linux':
        return _readLinuxProcNetDev();
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
        );
    }
  }

  Future<TrafficSnapshot> _readPlatformChannel() async {
    try {
      final response =
          await _channel.invokeMapMethod<String, dynamic>('getTrafficStats');
      return TrafficSnapshot(
        receivedBytes: (response?['rxBytes'] as num?)?.toInt() ??
            (response?['receivedBytes'] as num?)?.toInt() ??
            0,
        transmittedBytes: (response?['txBytes'] as num?)?.toInt() ??
            (response?['transmittedBytes'] as num?)?.toInt() ??
            0,
        timestamp: DateTime.now(),
      );
    } on MissingPluginException {
      return TrafficSnapshot(
        receivedBytes: 0,
        transmittedBytes: 0,
        timestamp: DateTime.now(),
      );
    } catch (error, stackTrace) {
      AppLogger.warning('Traffic stats unavailable from platform channel.');
      AppLogger.error('Traffic stats channel error',
          error: error, stackTrace: stackTrace);
      return TrafficSnapshot(
        receivedBytes: 0,
        transmittedBytes: 0,
        timestamp: DateTime.now(),
      );
    }
  }

  Future<TrafficSnapshot> _readLinuxProcNetDev() async {
    try {
      final content = await File('/proc/net/dev').readAsString();
      final lines = const LineSplitter().convert(content).skip(2);
      var rx = 0;
      var tx = 0;
      for (final line in lines) {
        final normalized = line.trim();
        if (normalized.isEmpty || !normalized.contains(':')) {
          continue;
        }
        final parts = normalized.split(':');
        final interfaceName = parts.first.trim();
        if (interfaceName == 'lo' || interfaceName.startsWith('docker')) {
          continue;
        }
        final stats = parts.last.trim().split(RegExp(r'\s+'));
        if (stats.length < 9) {
          continue;
        }
        rx += int.tryParse(stats[0]) ?? 0;
        tx += int.tryParse(stats[8]) ?? 0;
      }
      return TrafficSnapshot(
        receivedBytes: rx,
        transmittedBytes: tx,
        timestamp: DateTime.now(),
      );
    } catch (error, stackTrace) {
      AppLogger.warning('Unable to read /proc/net/dev for traffic stats.');
      AppLogger.error('Linux traffic stats error',
          error: error, stackTrace: stackTrace);
      return TrafficSnapshot(
        receivedBytes: 0,
        transmittedBytes: 0,
        timestamp: DateTime.now(),
      );
    }
  }
}

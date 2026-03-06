import 'dart:math' as math;

import '../../core/models/server_region.dart';

String formatDataRate(double valueMbps) {
  if (valueMbps >= 1000) {
    return '${(valueMbps / 1000).toStringAsFixed(2)} Gbps';
  }
  if (valueMbps >= 100) {
    return '${valueMbps.toStringAsFixed(0)} Mbps';
  }
  return '${valueMbps.toStringAsFixed(1)} Mbps';
}

String formatBytesCompact(int bytes) {
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  final fractionDigits = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
  return '${value.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
}

String formatDurationClock(Duration duration) {
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

String flagEmoji(String? countryCode) {
  final code = (countryCode ?? '').trim().toUpperCase();
  if (code.length != 2) {
    return '🌐';
  }
  final runes = code.runes
      .map((int rune) => rune + 127397)
      .map(String.fromCharCode)
      .join();
  return runes.isEmpty ? '🌐' : runes;
}

String latencyLabel(int? latencyMs) {
  if (latencyMs == null) return 'Latency unavailable';
  return '$latencyMs ms';
}

int estimateServerLoad(ServerRegion server) {
  final health = (server.regionHealthStatus ?? server.healthStatus ?? '')
      .trim()
      .toLowerCase();
  if (health == 'down') return 100;
  if (server.latencyPriority != null) {
    return (18 + server.latencyPriority! * 11).clamp(18, 95);
  }
  if (server.latencyMs != null) {
    return (22 + math.min(server.latencyMs!, 180) * 0.36).round().clamp(18, 92);
  }
  return 46;
}

String estimateServerLoadLabel(ServerRegion server) {
  return '${estimateServerLoad(server)}%';
}

import 'package:flutter/foundation.dart';

const String secureWaveRouteGuardStartMarker = '# SECUREWAVE_ROUTE_GUARD_START';
const String secureWaveRouteGuardEndMarker = '# SECUREWAVE_ROUTE_GUARD_END';

String buildLinuxWireGuardRuntimeConfig(
  String rawConfig, {
  required String apiBaseUrl,
}) {
  // The backend-issued Linux profile is authoritative. It already includes the
  // Table=off policy-routing hooks used by wg-quick on Linux, so the client
  // must not inject an additional iptables-based kill switch layer on top.
  //
  // We only strip the legacy SecureWave-managed route-guard block so older
  // cached configs can be normalized before they are handed to the native
  // runtime again.
  final normalized = rawConfig.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = _stripManagedRouteGuardBlock(
    normalized.split('\n'),
  );
  return '${lines.join('\n').trimRight()}\n';
}

@visibleForTesting
String? extractEndpointHostForKillSwitch(String rawConfig) {
  return _extractEndpointHost(rawConfig);
}

List<String> _stripManagedRouteGuardBlock(List<String> lines) {
  final next = <String>[];
  var skipping = false;
  for (final raw in lines) {
    final trimmed = raw.trim();
    if (trimmed == secureWaveRouteGuardStartMarker) {
      skipping = true;
      continue;
    }
    if (trimmed == secureWaveRouteGuardEndMarker) {
      skipping = false;
      continue;
    }
    if (!skipping) {
      next.add(raw);
    }
  }
  return next;
}

String? _extractEndpointHost(String rawConfig) {
  final normalized = rawConfig.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  for (final rawLine in normalized.split('\n')) {
    final line = rawLine.trim();
    if (!line.toLowerCase().startsWith('endpoint')) {
      continue;
    }
    final separator = line.indexOf('=');
    if (separator < 0 || separator == line.length - 1) {
      continue;
    }
    final value = line.substring(separator + 1).trim();
    if (value.isEmpty) {
      continue;
    }
    if (value.startsWith('[')) {
      final end = value.indexOf(']');
      if (end > 1) {
        return value.substring(1, end).trim();
      }
      continue;
    }
    final lastColon = value.lastIndexOf(':');
    if (lastColon <= 0) {
      return value;
    }
    return value.substring(0, lastColon).trim();
  }
  return null;
}

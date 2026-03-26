import 'package:flutter/foundation.dart';

const String secureWaveRouteGuardStartMarker = '# SECUREWAVE_ROUTE_GUARD_START';
const String secureWaveRouteGuardEndMarker = '# SECUREWAVE_ROUTE_GUARD_END';
const bool _uiAutomationEnabled =
    bool.fromEnvironment('SECUREWAVE_UI_AUTOMATION', defaultValue: false);

String buildLinuxWireGuardRuntimeConfig(
  String rawConfig, {
  required String apiBaseUrl,
  bool uiAutomationEnabled = _uiAutomationEnabled,
}) {
  // The backend-issued Linux profile is authoritative. It already includes the
  // Table=off policy-routing hooks used by wg-quick on Linux, so the client
  // must not inject an additional iptables-based kill switch layer on top.
  //
  // We only strip the legacy SecureWave-managed route-guard block so older
  // cached configs can be normalized before they are handed to the native
  // runtime again.
  final normalized = rawConfig.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  var lines = _stripManagedRouteGuardBlock(
    normalized.split('\n'),
  );
  if (uiAutomationEnabled) {
    final apiHost = _extractApiHost(apiBaseUrl);
    if (apiHost != null && apiHost.isNotEmpty) {
      lines = _insertAutomationRouteGuard(lines, apiHost);
    }
  }
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

List<String> _insertAutomationRouteGuard(List<String> lines, String apiHost) {
  final insertIndex = _findPeerInsertIndex(lines);
  return <String>[
    ...lines.take(insertIndex),
    secureWaveRouteGuardStartMarker,
    'PreUp = /bin/sh -c "'
        'API_HOST=\\"$apiHost\\"; '
        'API_IPS=\\\$(getent ahostsv4 \\"\\\$API_HOST\\" | awk \'{print \\\$1}\' | sort -u); '
        'GW=\\\$(ip route show default 0.0.0.0/0 | awk \'{print \\\$3; exit}\'); '
        'DEV=\\\$(ip route show default 0.0.0.0/0 | awk \'{print \\\$5; exit}\'); '
        '[ -n \\"\\\$GW\\" ] && [ -n \\"\\\$DEV\\" ] || exit 0; '
        'for ip in \\\$API_IPS; do ip route replace \\"\\\$ip/32\\" via \\"\\\$GW\\" dev \\"\\\$DEV\\" metric 5; done"',
    'PostDown = /bin/sh -c "'
        'API_HOST=\\"$apiHost\\"; '
        'API_IPS=\\\$(getent ahostsv4 \\"\\\$API_HOST\\" | awk \'{print \\\$1}\' | sort -u); '
        'for ip in \\\$API_IPS; do ip route del \\"\\\$ip/32\\" 2>/dev/null || true; done"',
    secureWaveRouteGuardEndMarker,
    '',
    ...lines.skip(insertIndex),
  ];
}

int _findPeerInsertIndex(List<String> lines) {
  for (var index = 0; index < lines.length; index++) {
    if (lines[index].trim().toLowerCase() == '[peer]') {
      return index;
    }
  }
  return lines.length;
}

String? _extractApiHost(String apiBaseUrl) {
  final uri = Uri.tryParse(apiBaseUrl.trim());
  final host = uri?.host.trim();
  if (host == null || host.isEmpty) {
    return null;
  }
  return host;
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

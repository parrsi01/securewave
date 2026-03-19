import 'package:flutter/foundation.dart';

class MockVpnAdapterConfig {
  const MockVpnAdapterConfig({
    required this.forceFailure,
    required this.latencyMs,
    required this.unstableMode,
  });

  final bool forceFailure;
  final int latencyMs;
  final bool unstableMode;

  Duration get latency {
    final normalized = latencyMs <= 0 ? 300 : latencyMs;
    return Duration(milliseconds: normalized.clamp(1, 60000));
  }
}

const bool isMockVpn =
    bool.fromEnvironment('SECUREWAVE_MOCK_VPN', defaultValue: false);

const MockVpnAdapterConfig mockVpnAdapterConfig = MockVpnAdapterConfig(
  forceFailure: bool.fromEnvironment(
    'SECUREWAVE_MOCK_VPN_FORCE_FAILURE',
    defaultValue: false,
  ),
  latencyMs: int.fromEnvironment(
    'SECUREWAVE_MOCK_VPN_LATENCY_MS',
    defaultValue: 300,
  ),
  unstableMode: bool.fromEnvironment(
    'SECUREWAVE_MOCK_VPN_UNSTABLE',
    defaultValue: false,
  ),
);

void validateProductionRuntimeConfig({
  bool isReleaseMode = kReleaseMode,
  bool? mockVpnEnabled,
  MockVpnAdapterConfig? mockConfig,
}) {
  if (!isReleaseMode) {
    return;
  }

  final effectiveMockVpn = mockVpnEnabled ?? isMockVpn;
  final effectiveConfig = mockConfig ?? mockVpnAdapterConfig;
  final violations = <String>[];

  if (effectiveMockVpn) {
    violations.add('SECUREWAVE_MOCK_VPN');
  }
  if (effectiveConfig.forceFailure) {
    violations.add('SECUREWAVE_MOCK_VPN_FORCE_FAILURE');
  }
  if (effectiveConfig.unstableMode) {
    violations.add('SECUREWAVE_MOCK_VPN_UNSTABLE');
  }
  if (effectiveConfig.latencyMs != 300) {
    violations.add('SECUREWAVE_MOCK_VPN_LATENCY_MS');
  }

  if (violations.isEmpty) {
    return;
  }

  throw StateError(
    'Refusing release startup with mock VPN settings enabled: '
    '${violations.join(', ')}.',
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:securewave_app/core/config/runtime_config.dart';

void main() {
  test('validateProductionRuntimeConfig allows default release config', () {
    expect(
      () => validateProductionRuntimeConfig(
        isReleaseMode: true,
        mockVpnEnabled: false,
        mockConfig: const MockVpnAdapterConfig(
          forceFailure: false,
          latencyMs: 300,
          unstableMode: false,
        ),
      ),
      returnsNormally,
    );
  });

  test('validateProductionRuntimeConfig rejects mock VPN in release', () {
    expect(
      () => validateProductionRuntimeConfig(
        isReleaseMode: true,
        mockVpnEnabled: true,
        mockConfig: const MockVpnAdapterConfig(
          forceFailure: false,
          latencyMs: 300,
          unstableMode: false,
        ),
      ),
      throwsStateError,
    );
  });

  test('validateProductionRuntimeConfig rejects non-default mock tuning in release', () {
    expect(
      () => validateProductionRuntimeConfig(
        isReleaseMode: true,
        mockVpnEnabled: false,
        mockConfig: const MockVpnAdapterConfig(
          forceFailure: false,
          latencyMs: 450,
          unstableMode: true,
        ),
      ),
      throwsStateError,
    );
  });
}

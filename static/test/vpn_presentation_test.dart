import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/vpn_state.dart';

void main() {
  test('VpnState.statusText surfaces specific error causes', () {
    expect(
      const VpnState(status: VpnStatus.error, errorKind: VpnErrorKind.backendUnreachable)
          .statusText(),
      'Server unreachable',
    );
    expect(
      const VpnState(status: VpnStatus.error, errorKind: VpnErrorKind.backendError)
          .statusText(),
      'Server error',
    );
    expect(
      const VpnState(status: VpnStatus.error, errorKind: VpnErrorKind.permissionRequired)
          .statusText(),
      'Permission needed',
    );
    expect(
      const VpnState(status: VpnStatus.error, errorKind: VpnErrorKind.nativeUnavailable)
          .statusText(),
      'VPN runtime missing',
    );
  });
}


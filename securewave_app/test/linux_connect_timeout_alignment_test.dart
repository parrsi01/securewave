import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/services/vpn_service.dart';
import 'package:securewave_app/core/state/vpn_state_machine.dart';

void main() {
  test('linux native connect timeout stays below the state-machine timeout', () {
    const config = VpnStateMachineConfig();

    expect(
      ChannelVpnService.linuxNativeConnectTimeout,
      lessThan(config.connectTimeout),
      reason:
          'The state machine must wait longer than the Linux native connect '
          'path so Dart surfaces the native result instead of timing out first.',
    );
  });
}

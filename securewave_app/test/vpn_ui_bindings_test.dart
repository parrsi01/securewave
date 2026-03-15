import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/models/vpn_status.dart';
import 'package:securewave_app/core/state/vpn_state.dart';
import 'package:securewave_app/ui/widgets/vpn_ui_bindings.dart';

void main() {
  test('UI binding resolves primary action from visual state', () {
    expect(
      resolveConnectionPrimaryAction(ConnectionVisualState.disconnected),
      ConnectionPrimaryAction.connect,
    );
    expect(
      resolveConnectionPrimaryAction(ConnectionVisualState.connected),
      ConnectionPrimaryAction.disconnect,
    );
    expect(
      resolveConnectionPrimaryAction(ConnectionVisualState.connecting),
      ConnectionPrimaryAction.none,
    );
    expect(
      resolveConnectionPrimaryAction(ConnectionVisualState.reconnecting),
      ConnectionPrimaryAction.none,
    );
    expect(
      resolveConnectionPrimaryAction(ConnectionVisualState.disconnecting),
      ConnectionPrimaryAction.none,
    );
    expect(
      resolveConnectionPrimaryAction(ConnectionVisualState.error),
      ConnectionPrimaryAction.connect,
    );
  });

  test(
      'UI binding marks only active or transitional tunnel states as live switching',
      () {
    expect(
      connectionVisualStateSupportsLiveSwitch(
          ConnectionVisualState.disconnected),
      isFalse,
    );
    expect(
      connectionVisualStateSupportsLiveSwitch(ConnectionVisualState.error),
      isFalse,
    );
    expect(
      connectionVisualStateSupportsLiveSwitch(ConnectionVisualState.connected),
      isTrue,
    );
    expect(
      connectionVisualStateSupportsLiveSwitch(ConnectionVisualState.connecting),
      isTrue,
    );
    expect(
      connectionVisualStateSupportsLiveSwitch(
          ConnectionVisualState.reconnecting),
      isTrue,
    );
    expect(
      connectionVisualStateSupportsLiveSwitch(
          ConnectionVisualState.disconnecting),
      isTrue,
    );
  });

  test('UI binding keeps error visually distinct from active tunnel state', () {
    final visual = resolveConnectionVisualState(
      const VpnState(status: VpnStatus.error),
    );

    expect(visual, ConnectionVisualState.error);
    expect(connectionVisualStateHasActiveTunnel(visual), isFalse);
    expect(connectionVisualStateIsBusy(visual), isFalse);
  });

  test('UI binding shows reconnecting while auto-reconnect is pending', () {
    final visual = resolveConnectionVisualState(
      const VpnState(
        status: VpnStatus.disconnected,
        desiredOn: true,
        reconnectPending: true,
      ),
    );

    expect(visual, ConnectionVisualState.reconnecting);
    expect(connectionVisualStateIsBusy(visual), isTrue);
  });
}

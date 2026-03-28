import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/vpn_protocol.dart';
import '../../core/models/vpn_status.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_ui_v1.dart';
import '../../ui/components/depth_panel.dart';
import '../../ui/status_indicator.dart';

class ConnectionPage extends ConsumerWidget {
  const ConnectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);

    final steps = <MapEntry<String, bool>>[
      MapEntry('AUTH', vpnState.connectPhase != null),
      MapEntry(
          'BACKEND',
          vpnState.connectPhase != null &&
              vpnState.connectPhase!.index >=
                  ConnectPhase.checkingBackend.index),
      MapEntry(
          'PROTOCOL',
          vpnState.connectPhase != null &&
              vpnState.connectPhase!.index >=
                  ConnectPhase.resolvingProtocol.index),
      MapEntry(
          'PROFILE',
          vpnState.connectPhase != null &&
              vpnState.connectPhase!.index >=
                  ConnectPhase.fetchingProfile.index),
      MapEntry(
          'TUNNEL',
          vpnState.connectPhase != null &&
              vpnState.connectPhase!.index >=
                  ConnectPhase.establishingTunnel.index),
      MapEntry(
          'VERIFY',
          vpnState.connectPhase != null &&
              vpnState.connectPhase!.index >=
                  ConnectPhase.verifyingConnection.index),
    ];

    final statusLabel = switch (vpnState.status) {
      VpnStatus.connected => 'Connected',
      VpnStatus.connecting => 'Connecting',
      VpnStatus.verifying => 'Verifying',
      VpnStatus.disconnecting => 'Disconnecting',
      VpnStatus.reconnecting => 'Reconnecting',
      VpnStatus.degraded => 'Degraded',
      VpnStatus.error => 'Error',
      VpnStatus.disconnected => 'Disconnected',
    };

    final protocolLabel = vpnState.protocol == VpnProtocol.auto
        ? 'Auto${vpnState.effectiveProtocol == null ? '' : ' → ${vpnProtocolLabel(vpnState.effectiveProtocol!)}'}'
        : vpnProtocolLabel(vpnState.effectiveProtocol ?? vpnState.protocol);

    final durationLabel = vpnState.lastTunnelStartAt == null
        ? '--:--:--'
        : AppUIv1.formatDuration(
            DateTime.now().difference(vpnState.lastTunnelStartAt!));

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppUIv1.space5),
        children: [
          Text('Connection', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppUIv1.space3),
          StatusIndicator(
              status: vpnState.status, label: statusLabel, large: true),
          const SizedBox(height: AppUIv1.space4),
          DepthPanel(
            depth: PanelDepth.floating,
            padding: const EdgeInsets.all(AppUIv1.space4),
            child: Column(
              children: [
                _Row(
                    label: 'Selected server',
                    value: vpnState.selectedServerId ?? 'None'),
                const SizedBox(height: AppUIv1.space3),
                _Row(label: 'Protocol', value: protocolLabel),
                const SizedBox(height: AppUIv1.space3),
                _Row(label: 'Duration', value: durationLabel),
                const SizedBox(height: AppUIv1.space3),
                _Row(
                  label: 'Validation',
                  value:
                      '${vpnState.validationScore}% (${vpnState.validationStatus.name})',
                ),
                const SizedBox(height: AppUIv1.space3),
                _Row(
                  label: 'Session usage',
                  value: AppUIv1.formatDataAmount(
                      vpnState.sessionTransferredBytes),
                ),
                const SizedBox(height: AppUIv1.space3),
                _Row(
                  label: 'Desired protection',
                  value: vpnState.desiredOn ? 'On' : 'Off',
                ),
                if (vpnState.killSwitchActive) ...[
                  const SizedBox(height: AppUIv1.space3),
                  const _Row(
                    label: 'Kill switch',
                    value: 'Active',
                  ),
                ],
                if (vpnState.failoverActive) ...[
                  const SizedBox(height: AppUIv1.space3),
                  _Row(
                    label: 'Failover',
                    value: vpnState.failoverReason ?? 'Active',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppUIv1.space4),
          Text('Pipeline', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space3),
          ...steps.map(
            (step) => Padding(
              padding: const EdgeInsets.only(bottom: AppUIv1.space2),
              child: DepthPanel(
                depth: step.value ? PanelDepth.raised : PanelDepth.base,
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(
                    step.value
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: step.value ? AppUIv1.success : AppUIv1.inkSoft,
                  ),
                  title: Text(step.key),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DepthPanel(
      depth: PanelDepth.base,
      padding: const EdgeInsets.symmetric(
        horizontal: AppUIv1.space3,
        vertical: AppUIv1.space3,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: AppUIv1.space3),
          Flexible(
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

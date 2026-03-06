import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/vpn_protocol.dart';
import '../../core/models/vpn_status.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/components/dashboard_card.dart';
import '../../ui/components/section_container.dart';
import '../../ui/components/status_indicator.dart';
import '../../ui/layout/adaptive_shell_scaffold.dart';
import '../../ui/theme/spacing.dart';

class ConnectionPage extends ConsumerWidget {
  const ConnectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final steps = <MapEntry<String, bool>>[
      MapEntry('LOGIN', vpnState.stage.index >= VpnConnectionStage.login.index),
      MapEntry('FETCH_SERVERS',
          vpnState.stage.index >= VpnConnectionStage.fetchServers.index),
      MapEntry('FETCH_PROFILE',
          vpnState.stage.index >= VpnConnectionStage.fetchProfile.index),
      MapEntry('PROTOCOL_READY',
          vpnState.stage.index >= VpnConnectionStage.protocolReady.index),
      MapEntry('TUNNEL_START',
          vpnState.stage.index >= VpnConnectionStage.tunnelStart.index),
      MapEntry('TUNNEL_ACTIVE',
          vpnState.stage.index >= VpnConnectionStage.tunnelActive.index),
    ];

    final statusLabel = switch (vpnState.status) {
      VpnStatus.connected => 'Connected',
      VpnStatus.connecting => 'Connecting',
      VpnStatus.disconnecting => 'Disconnecting',
      VpnStatus.reconnecting => 'Reconnecting',
      VpnStatus.error => 'Error',
      VpnStatus.disconnected => 'Disconnected',
    };

    final protocolLabel = vpnState.protocol == VpnProtocol.auto
        ? 'Auto${vpnState.activeProtocol == null ? '' : ' → ${vpnProtocolLabel(vpnState.activeProtocol!)}'}'
        : vpnProtocolLabel(vpnState.activeProtocol ?? vpnState.protocol);

    return AdaptiveShellScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionContainer(
            title: 'Connection details',
            subtitle: 'A clean tunnel status view with pipeline progress.',
            trailing:
                StatusIndicator(status: vpnState.status, label: statusLabel),
            child: DashboardCard(
              child: Column(
                children: [
                  _Row(
                    label: 'Selected server',
                    value: vpnState.selectedServerId ?? 'None',
                  ),
                  const SizedBox(height: SecureWaveSpacing.md),
                  _Row(label: 'Protocol', value: protocolLabel),
                  const SizedBox(height: SecureWaveSpacing.md),
                  _Row(
                    label: 'Interface',
                    value: vpnState.interfaceName ?? 'Not detected',
                  ),
                  const SizedBox(height: SecureWaveSpacing.md),
                  _Row(
                    label: 'Duration',
                    value: _formatDuration(vpnState.connectionDuration),
                  ),
                  const SizedBox(height: SecureWaveSpacing.md),
                  _Row(
                    label: 'Routing',
                    value: vpnState.routingOk ? 'OK' : 'Pending / conflict',
                  ),
                  const SizedBox(height: SecureWaveSpacing.md),
                  _Row(
                    label: 'Session usage',
                    value: _formatDataAmount(
                      vpnState.sessionDownloadBytes +
                          vpnState.sessionUploadBytes,
                    ),
                  ),
                  const SizedBox(height: SecureWaveSpacing.md),
                  _Row(
                    label: 'Reconnect attempts',
                    value: '${vpnState.reconnectAttempt}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SecureWaveSpacing.xl),
          SectionContainer(
            title: 'Pipeline',
            subtitle:
                'Connection stages update in order as the tunnel comes up.',
            child: Column(
              children: [
                for (var index = 0; index < steps.length; index++) ...[
                  DashboardCard(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        steps[index].value
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                      ),
                      title: Text(steps[index].key),
                    ),
                  ),
                  if (index != steps.length - 1)
                    const SizedBox(height: SecureWaveSpacing.md),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatDataAmount(int bytes) {
    final kb = bytes / 1024;
    final mb = kb / 1024;
    final gb = mb / 1024;
    if (gb >= 1) {
      return '${gb.toStringAsFixed(2)} GB';
    }
    if (mb >= 1) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    if (kb >= 1) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
  }
}

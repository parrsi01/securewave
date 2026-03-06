import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/vpn_status.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_ui_v1.dart';
import '../../ui/status_indicator.dart';

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

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppUIv1.space5),
        children: [
          Text('Connection', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppUIv1.space3),
          StatusIndicator(
              status: vpnState.status, label: statusLabel, large: true),
          const SizedBox(height: AppUIv1.space4),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppUIv1.space4),
              child: Column(
                children: [
                  _Row(
                      label: 'Selected server',
                      value: vpnState.selectedServerId ?? 'None'),
                  const SizedBox(height: AppUIv1.space3),
                  _Row(label: 'Protocol', value: vpnState.protocol.name),
                  const SizedBox(height: AppUIv1.space3),
                  _Row(
                      label: 'Interface',
                      value: vpnState.interfaceName ?? 'Not detected'),
                  const SizedBox(height: AppUIv1.space3),
                  _Row(
                      label: 'Duration',
                      value:
                          AppUIv1.formatDuration(vpnState.connectionDuration)),
                  const SizedBox(height: AppUIv1.space3),
                  _Row(
                      label: 'Routing',
                      value: vpnState.routingOk ? 'OK' : 'Pending'),
                  const SizedBox(height: AppUIv1.space3),
                  _Row(
                    label: 'Session usage',
                    value: AppUIv1.formatDataAmount(
                      vpnState.sessionDownloadBytes +
                          vpnState.sessionUploadBytes,
                    ),
                  ),
                  const SizedBox(height: AppUIv1.space3),
                  _Row(
                      label: 'Reconnect attempts',
                      value: '${vpnState.reconnectAttempt}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppUIv1.space4),
          Text('Pipeline', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space3),
          ...steps.map(
            (step) => Padding(
              padding: const EdgeInsets.only(bottom: AppUIv1.space2),
              child: Card(
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Flexible(
          child: Text(
            value,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

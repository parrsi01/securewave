import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/vpn_status.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_ui_v1.dart';

class VpnPage extends ConsumerWidget {
  const VpnPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final servers = ref.watch(serversProvider);

    final serversData = servers.maybeWhen(data: (data) => data, orElse: () => null);
    if (serversData != null && serversData.isNotEmpty && vpnState.selectedServerId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(vpnStateProvider.notifier).selectServer(serversData.first.id);
      });
    }

    final selectedServerLabel = serversData == null || serversData.isEmpty
        ? 'Auto-select'
        : serversData
                .firstWhere(
                  (server) => server.id == vpnState.selectedServerId,
                  orElse: () => serversData.first,
                )
                .name;

    final statusText = switch (vpnState.status) {
      VpnStatus.connected => 'Connected',
      VpnStatus.connecting => 'Connecting',
      VpnStatus.error => 'Needs attention',
      VpnStatus.disconnected => 'Disconnected',
    };

    final statusColor = switch (vpnState.status) {
      VpnStatus.connected => AppUIv1.success,
      VpnStatus.connecting => AppUIv1.accentSun,
      VpnStatus.error => AppUIv1.warning,
      VpnStatus.disconnected => AppUIv1.inkSoft,
    };
    final primaryActionLabel = vpnState.status == VpnStatus.connecting
        ? 'Connecting...'
        : vpnState.status == VpnStatus.connected
            ? 'Disconnect'
            : 'Connect';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppUIv1.space5),
        children: [
          Text('Connection', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppUIv1.space3),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppUIv1.space5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Status', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: AppUIv1.space2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(statusText, style: Theme.of(context).textTheme.titleLarge),
                      Chip(
                        label: Text(statusText),
                        backgroundColor: statusColor.withValues(alpha: 0.15),
                        labelStyle: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppUIv1.space4),
                  Text('Selected region', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: AppUIv1.space1),
                  Text(selectedServerLabel, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppUIv1.space4),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: vpnState.isBusy
                          ? null
                          : () {
                              if (vpnState.status == VpnStatus.connected) {
                                ref.read(vpnStateProvider.notifier).disconnect();
                              } else {
                                ref.read(vpnStateProvider.notifier).connect();
                              }
                            },
                      child: Text(primaryActionLabel),
                    ),
                  ),
                  const SizedBox(height: AppUIv1.space3),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/servers'),
                      icon: const Icon(Icons.public),
                      label: const Text('Choose a server'),
                    ),
                  ),
                  if (vpnState.errorMessage != null) ...[
                    const SizedBox(height: AppUIv1.space3),
                    Text(
                      vpnState.errorMessage!,
                      style: const TextStyle(color: AppUIv1.warning),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppUIv1.space4),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppUIv1.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Live activity', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppUIv1.space2),
                  Text('Download: ${vpnState.dataRateDown.toStringAsFixed(1)} Mbps'),
                  const SizedBox(height: AppUIv1.space1),
                  Text('Upload: ${vpnState.dataRateUp.toStringAsFixed(1)} Mbps'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

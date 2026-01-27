import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/app_state.dart';
import '../../core/services/vpn_service.dart';
import '../../ui/app_ui_v1.dart';
import 'vpn_controller.dart';

class VpnPage extends ConsumerWidget {
  const VpnPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnControllerProvider);
    final servers = ref.watch(serversProvider);
    final status = ref.watch(vpnStatusProvider);
    final vpnService = ref.watch(vpnServiceProvider);
    String? platformNotice;
    if (vpnService is VpnServiceUnsupported) {
      platformNotice = vpnService.message;
    }

    final serversData = servers.maybeWhen(data: (data) => data, orElse: () => null);
    if (serversData != null && serversData.isNotEmpty && vpnState.selectedServerId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(vpnControllerProvider.notifier).selectServer(
              serversData.first['server_id'] as String?,
            );
      });
    }

    final selectedServerLabel = serversData == null || serversData.isEmpty
        ? 'Auto-select'
        : serversData
                .firstWhere(
                  (server) => server['server_id'] == vpnState.selectedServerId,
                  orElse: () => serversData.first,
                )['location']
                ?.toString() ??
            'Auto-select';

    final statusText = status.when(
      data: (data) {
        switch (data) {
          case VpnStatus.connected:
            return 'Connected';
          case VpnStatus.connecting:
            return 'Connecting';
          case VpnStatus.disconnecting:
            return 'Disconnecting';
          case VpnStatus.disconnected:
            return 'Disconnected';
        }
      },
      loading: () => 'Checking',
      error: (_, __) => 'Unavailable',
    );

    final statusColor = status.when(
      data: (data) {
        switch (data) {
          case VpnStatus.connected:
            return AppUIv1.success;
          case VpnStatus.connecting:
            return AppUIv1.accentSun;
          case VpnStatus.disconnecting:
            return AppUIv1.accentSun;
          case VpnStatus.disconnected:
            return AppUIv1.inkSoft;
        }
      },
      loading: () => AppUIv1.inkSoft,
      error: (_, __) => AppUIv1.inkSoft,
    );

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppUIv1.space5),
        children: [
          Text('Connection', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppUIv1.space3),
          if (platformNotice != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppUIv1.space4),
                child: Text(platformNotice, style: Theme.of(context).textTheme.bodyMedium),
              ),
            ),
          if (platformNotice != null) const SizedBox(height: AppUIv1.space3),
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
                                ref.read(vpnControllerProvider.notifier).disconnect();
                              } else {
                                ref.read(vpnControllerProvider.notifier).connect();
                              }
                            },
                      child: Text(
                        vpnState.status == VpnStatus.connected ? 'Disconnect' : 'Connect',
                      ),
                    ),
                  ),
                  const SizedBox(height: AppUIv1.space3),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.go('/servers'),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/app_state.dart';
import '../../core/services/vpn_service.dart';
import '../../widgets/buttons/primary_button.dart';
import '../../widgets/buttons/secondary_button.dart';
import '../../widgets/layouts/content_layout.dart';
import '../../widgets/layouts/section_header.dart';
import '../../widgets/loaders/app_loader.dart';
import '../../widgets/loaders/inline_banner.dart';
import 'vpn_controller.dart';

class VpnPage extends ConsumerWidget {
  const VpnPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnControllerProvider);
    final servers = ref.watch(serversProvider);
    final status = ref.watch(vpnStatusProvider);

    return SafeArea(
      child: ContentLayout(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const SectionHeader(
              title: 'Provision VPN access',
              subtitle: 'Choose a region here, connect inside the SecureWave app.',
            ),
            const SizedBox(height: 20),
            servers.when(
              data: (data) {
                return DropdownButtonFormField<String>(
                  value: vpnState.selectedServerId,
                  decoration: const InputDecoration(labelText: 'Server region'),
                  items: data
                      .map((server) => DropdownMenuItem<String>(
                            value: server['server_id'] as String?,
                            child: Text(server['location'] ?? 'Unknown'),
                          ))
                      .toList(),
                  onChanged: (value) => ref.read(vpnControllerProvider.notifier).selectServer(value),
                );
              },
              loading: () => const AppLoader(),
              error: (_, __) =>
                  const InlineBanner(message: 'Unable to load servers. Check your connection and try again.'),
            ),
            const SizedBox(height: 20),
            status.when(
              data: (data) => _StatusPanel(status: data, vpnState: vpnState),
              loading: () => const AppLoader(),
              error: (_, __) => const InlineBanner(message: 'Unable to read VPN status. Please refresh.'),
            ),
            if (vpnState.errorMessage != null) ...[
              const SizedBox(height: 12),
              InlineBanner(message: vpnState.errorMessage!),
            ],
            const SizedBox(height: 20),
            PrimaryButton(
              label: _primaryLabel(vpnState.status),
              isLoading: vpnState.isBusy,
              onPressed: vpnState.isBusy
                  ? null
                  : () {
                      if (vpnState.status == VpnStatus.connected) {
                        ref.read(vpnControllerProvider.notifier).disconnect();
                      } else {
                        ref.read(vpnControllerProvider.notifier).connect();
                      }
                    },
            ),
            const SizedBox(height: 12),
            SecondaryButton(
              label: 'Run diagnostics',
              onPressed: () => context.go('/tests'),
            ),
          ],
        ),
      ),
    );
  }

  String _primaryLabel(VpnStatus status) {
    switch (status) {
      case VpnStatus.connected:
        return 'Disconnect';
      case VpnStatus.connecting:
        return 'Connecting...';
      case VpnStatus.disconnecting:
        return 'Disconnecting...';
      case VpnStatus.disconnected:
        return 'Connect';
    }
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.status, required this.vpnState});

  final VpnStatus status;
  final VpnUiState vpnState;

  @override
  Widget build(BuildContext context) {
    final label = _statusLabel(status);
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Status: $label', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Download: ${vpnState.dataRateDown.toStringAsFixed(1)} Mbps'),
          Text('Upload: ${vpnState.dataRateUp.toStringAsFixed(1)} Mbps'),
          const SizedBox(height: 8),
          const Text('Connection happens in the SecureWave app.'),
        ],
      ),
    );
  }

  String _statusLabel(VpnStatus status) {
    switch (status) {
      case VpnStatus.connected:
        return 'Connected';
      case VpnStatus.connecting:
        return 'Connecting';
      case VpnStatus.disconnecting:
        return 'Disconnecting';
      case VpnStatus.disconnected:
        return 'Disconnected';
    }
  }

  Color _statusColor(VpnStatus status) {
    switch (status) {
      case VpnStatus.connected:
        return const Color(0xFF10B981);
      case VpnStatus.connecting:
        return const Color(0xFF38BDF8);
      case VpnStatus.disconnecting:
        return const Color(0xFFF59E0B);
      case VpnStatus.disconnected:
        return const Color(0xFF94A3B8);
    }
  }
}

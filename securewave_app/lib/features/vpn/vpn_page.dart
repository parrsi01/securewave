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
              subtitle: 'Choose a region here, then connect with SecureWave VPN.',
            ),
            const SizedBox(height: 20),
            servers.when(
              data: (data) {
                if (vpnState.selectedServerId == null && data.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    ref.read(vpnControllerProvider.notifier).selectServer(
                          data.first['server_id'] as String?,
                        );
                  });
                }
                final selected = data.firstWhere(
                  (server) => server['server_id'] == vpnState.selectedServerId,
                  orElse: () => {},
                );
                final selectedLabel = selected['location'] ?? 'Auto-select';
                return DropdownButtonFormField<String>(
                  value: vpnState.selectedServerId,
                  decoration: InputDecoration(
                    labelText: 'Server region',
                    helperText: 'Selected: $selectedLabel',
                  ),
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
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    status.when(
                      data: (data) => _StatusPanel(status: data, vpnState: vpnState),
                      loading: () => const AppLoader(),
                      error: (_, __) => const InlineBanner(message: 'Unable to read VPN status. Please refresh.'),
                    ),
                    if (vpnState.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      InlineBanner(message: vpnState.errorMessage!),
                    ],
                    const SizedBox(height: 16),
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
            ),
            const SizedBox(height: 24),
            const SectionHeader(
              title: 'Connection checklist',
              subtitle: 'If the tunnel does not connect, verify each step.',
            ),
            const SizedBox(height: 12),
            _TroubleshootingCard(
              items: const [
                'Allow VPN permissions when prompted.',
                'Keep SecureWave open until status turns Connected.',
                'If stuck, tap Disconnect, wait 5 seconds, then retry.',
                'Switch regions if the selected server is busy.',
              ],
            ),
            const SizedBox(height: 16),
            _TroubleshootingCard(
              title: 'When to contact support',
              items: const [
                'Status stays Connecting for more than 60 seconds.',
                'You see repeated provisioning errors.',
                'Speed tests drop below expected baseline.',
              ],
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
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              'Status: $label',
              key: ValueKey(label),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: status == VpnStatus.connected ? 1 : 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Download: ${vpnState.dataRateDown.toStringAsFixed(1)} Mbps'),
                Text('Upload: ${vpnState.dataRateUp.toStringAsFixed(1)} Mbps'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            vpnState.lastConfig == null ? 'Config: not provisioned yet' : 'Config: provisioned',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (vpnState.lastSessionId != null) ...[
            const SizedBox(height: 4),
            Text(
              'Session: ${vpnState.lastSessionId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          const Text('SecureWave connects using OS-level WireGuard tunnels.'),
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

class _TroubleshootingCard extends StatelessWidget {
  const _TroubleshootingCard({required this.items, this.title});

  final String? title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(title!, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
            ],
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

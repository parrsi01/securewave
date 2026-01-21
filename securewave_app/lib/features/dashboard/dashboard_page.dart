import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/app_state.dart';
import '../../core/services/vpn_service.dart';
import '../../widgets/cards/action_card.dart';
import '../../widgets/cards/metric_card.dart';
import '../../widgets/cards/status_chip.dart';
import '../../widgets/layouts/content_layout.dart';
import '../../widgets/layouts/section_header.dart';
import '../../widgets/loaders/app_loader.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnStatus = ref.watch(vpnStatusProvider);
    final usage = ref.watch(usageProvider);
    final deviceInfo = ref.watch(deviceInfoProvider);

    return SafeArea(
      child: ContentLayout(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const SectionHeader(
                title: 'SecureWave Control Center',
                subtitle: 'Manage your plan, devices, and secure access in one place.',
              ),
              const SizedBox(height: 16),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Account status', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('Active • Basic plan (5 GB/month)', style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                  const StatusChip(label: 'Secure', color: Color(0xFF10B981)),
                ],
              ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                MetricCard(label: 'Device', value: deviceInfo, icon: Icons.devices_other),
                vpnStatus.when(
                  data: (status) => MetricCard(
                    label: 'VPN status',
                    value: _vpnLabel(status),
                    icon: Icons.shield,
                  ),
                  loading: () => const MetricCard(
                    label: 'VPN status',
                    value: 'Checking...',
                    icon: Icons.shield,
                  ),
                  error: (_, __) => const MetricCard(
                    label: 'VPN status',
                    value: 'Unavailable',
                    icon: Icons.shield,
                  ),
                ),
                usage.when(
                  data: (data) => MetricCard(
                    label: 'Data usage',
                    value:
                        '${data['total_data_received_mb'] ?? 0} MB down • ${data['total_data_sent_mb'] ?? 0} MB up',
                    icon: Icons.insights,
                  ),
                  loading: () => const MetricCard(
                    label: 'Data usage',
                    value: 'Loading...',
                    icon: Icons.insights,
                  ),
                  error: (_, __) => const MetricCard(
                    label: 'Data usage',
                    value: 'Unavailable',
                    icon: Icons.insights,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
              const SectionHeader(
                title: 'Quick actions',
                subtitle: 'Provision access, manage devices, or run diagnostics.',
              ),
            const SizedBox(height: 12),
            ActionCard(
              title: 'Provision VPN access',
              subtitle: 'Select a server region and prep your device.',
              icon: Icons.shield_outlined,
              onTap: () => context.go('/vpn'),
            ),
            ActionCard(
              title: 'Manage devices',
              subtitle: 'Add, rename, or revoke access.',
              icon: Icons.devices,
              onTap: () => context.go('/devices'),
            ),
            ActionCard(
              title: 'Run diagnostics',
              subtitle: 'Check latency and leak protection.',
              icon: Icons.speed,
              onTap: () => context.go('/tests'),
            ),
            const SizedBox(height: 12),
          usage.when(
            loading: () => const AppLoader(size: 18),
            data: (_) => Text('VPN connection is managed by the SecureWave app.',
                style: Theme.of(context).textTheme.bodySmall),
            error: (_, __) => Text('VPN connection is managed by the SecureWave app.',
                style: Theme.of(context).textTheme.bodySmall),
          ),
          ],
        ),
      ),
    );
  }

  String _vpnLabel(VpnStatus status) {
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
}

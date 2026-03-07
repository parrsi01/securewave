import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/vpn_state.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/widgets/ui_helpers.dart';
import '../../ui/widgets/vpn_ui_bindings.dart';

/// VPN diagnostics screen.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final visualState = resolveConnectionVisualState(vpnState);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        centerTitle: false,
        actions: [
          if (Theme.of(context).platform == TargetPlatform.iOS ||
              Theme.of(context).platform == TargetPlatform.macOS)
            TextButton(
              onPressed: () => context.push('/diagnostics/apple'),
              child: const Text('Apple VPN'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        children: [
          _DiagRow(
            label: 'Status',
            value: visualState.name,
          ),
          _DiagRow(
            label: 'Protocol',
            value: vpnState.effectiveProtocol?.name.toUpperCase() ?? '--',
          ),
          _DiagRow(
            label: 'Server',
            value: vpnState.selectedServerId ?? 'None',
          ),
          _DiagRow(
            label: 'Download',
            value: formatDataRate(vpnState.dataRateDown),
          ),
          _DiagRow(
            label: 'Upload',
            value: formatDataRate(vpnState.dataRateUp),
          ),
          _DiagRow(
            label: 'Session bytes',
            value: formatBytesCompact(vpnState.sessionTransferredBytes),
          ),
          _DiagRow(
            label: 'Stability',
            value: '${(vpnState.stabilityScore * 100).round()}%',
          ),
          if (vpnState.failoverActive) ...[
            const SizedBox(height: AppSpacing.space4),
            Container(
              padding: const EdgeInsets.all(AppSpacing.space4),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(AppSpacing.radiusL),
              ),
              child: Text(
                'Failover active: ${vpnState.failoverReason ?? 'unknown reason'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.warning,
                    ),
              ),
            ),
          ],
          if (vpnState.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.space4),
            Container(
              padding: const EdgeInsets.all(AppSpacing.space4),
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(AppSpacing.radiusL),
              ),
              child: Text(
                'Error: ${vpnState.errorMessage}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DiagRow extends StatelessWidget {
  const _DiagRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.inkMuted,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

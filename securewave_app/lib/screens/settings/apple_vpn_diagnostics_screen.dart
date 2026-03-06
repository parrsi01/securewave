import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/vpn_platform_bridge.dart';
import '../../core/services/vpn_service.dart';
import '../../core/state/app_state.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';

class AppleVpnDiagnosticsSnapshot {
  const AppleVpnDiagnosticsSnapshot({
    required this.status,
    required this.diagnostics,
  });

  final VpnPlatformBridgeStatus status;
  final VpnPlatformBridgeDiagnostics diagnostics;
}

final appleVpnDiagnosticsProvider =
    FutureProvider.autoDispose<AppleVpnDiagnosticsSnapshot?>((ref) async {
  final service = ref.watch(vpnServiceProvider);
  if (service is! ChannelVpnService || !service.usesApplePlatformBridge) {
    return null;
  }
  final diagnostics = await service.fetchPlatformDiagnostics();
  final status = await service.fetchPlatformBridgeStatus();
  if (diagnostics == null || status == null) {
    return null;
  }
  return AppleVpnDiagnosticsSnapshot(
    status: status,
    diagnostics: diagnostics,
  );
});

class AppleVpnDiagnosticsScreen extends ConsumerWidget {
  const AppleVpnDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appleVpnDiagnosticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('VPN Diagnostics (Apple)'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(appleVpnDiagnosticsProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
          child: snapshot.when(
            loading: () => const _CenteredMessage(
              icon: Icons.hourglass_top_rounded,
              title: 'Loading native diagnostics...',
            ),
            error: (error, _) => _CenteredMessage(
              icon: Icons.error_outline_rounded,
              title: 'Unable to read Apple VPN diagnostics',
              detail: error.toString(),
            ),
            data: (data) {
              if (data == null) {
                return const _CenteredMessage(
                  icon: Icons.phone_disabled_outlined,
                  title: 'Apple VPN bridge is not active on this platform',
                );
              }

              final diagnostics = data.diagnostics;
              final status = data.status;
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.space4),
                children: [
                  _StatusCard(
                    title: 'Tunnel State',
                    value: status.state.name,
                    accent: status.isConnected
                        ? AppColors.success
                        : AppColors.primary,
                    subtitle: status.connectedSince == null
                        ? null
                        : 'Connected since ${status.connectedSince}',
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  _StatusCard(
                    title: 'Capability Presence',
                    value: diagnostics.available ? 'ready' : 'blocked',
                    accent: diagnostics.available
                        ? AppColors.success
                        : AppColors.warning,
                    subtitle: [
                      'extensionEmbedded=${diagnostics.extensionEmbedded}',
                      'appGroupConfigured=${diagnostics.appGroupConfigured}',
                      'tunnelManagerReady=${diagnostics.tunnelManagerReady}',
                    ].join(' • '),
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  _StatusCard(
                    title: 'Traffic Counters',
                    value: 'rx=${status.rxBytes} • tx=${status.txBytes}',
                    accent: AppColors.secondary,
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  _StatusCard(
                    title: 'Provider Bundle',
                    value: diagnostics.providerBundleIdentifier ?? 'unknown',
                    accent: AppColors.primary,
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  _StatusCard(
                    title: 'App Group',
                    value: diagnostics.appGroupIdentifier ?? 'unknown',
                    accent: AppColors.primary,
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  _StatusCard(
                    title: 'Last Native Error',
                    value: diagnostics.lastError ??
                        status.lastError ??
                        'none',
                    accent: diagnostics.lastError == null &&
                            status.lastError == null
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.space6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: AppColors.primary),
          const SizedBox(height: AppSpacing.space3),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (detail != null) ...[
            const SizedBox(height: AppSpacing.space2),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.value,
    required this.accent,
    this.subtitle,
  });

  final String title;
  final String value;
  final Color accent;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.space2),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

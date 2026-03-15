import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/server_region.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/widgets/vpn_ui_bindings.dart';
import 'status_indicator.dart';

/// Riverpod-wired status display.
///
/// Renders [StatusIndicator] plus contextual banners:
/// - Failover banner when [VpnState.failoverActive] is true
/// - Server health warnings (all servers down / selected region offline)
/// - Geographic optimisation hint for Caribbean routing
class StatusDisplay extends ConsumerWidget {
  const StatusDisplay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final visualState = resolveConnectionVisualState(vpnState);
    final serversAsync = ref.watch(serversProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatusIndicator(visualState: visualState),

        // ── Failover banner ────────────────────────────────────────────
        if (vpnState.failoverActive) ...[
          const SizedBox(height: AppSpacing.space3),
          _FailoverBanner(vpnState: vpnState),
        ],

        // ── Server-health banners (disconnected state) ─────────────────
        if (visualState == ConnectionVisualState.disconnected)
          serversAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (servers) =>
                _ServerHealthBanner(servers: servers, vpnState: vpnState),
          ),

        // ── Optimisation hint ──────────────────────────────────────────
        if (visualState == ConnectionVisualState.connected)
          serversAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (servers) =>
                _OptimisationHint(servers: servers, vpnState: vpnState),
          ),
      ],
    );
  }
}

// ── Failover banner ─────────────────────────────────────────────────────────

class _FailoverBanner extends ConsumerWidget {
  const _FailoverBanner({required this.vpnState});

  final VpnState vpnState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serversAsync = ref.watch(serversProvider);
    final fallbackServer = serversAsync.whenOrNull<ServerRegion?>(
      data: (servers) {
        if (vpnState.failoverRegionId == null) return null;
        for (final s in servers) {
          if (s.id == vpnState.failoverRegionId) return s;
        }
        return null;
      },
    );

    final regionGroup = fallbackServer?.regionGroup ?? '';
    final regionLabel = _regionGroupLabel(regionGroup);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Primary server unavailable. Connected via fallback region.',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          if (fallbackServer != null) ...[
            const SizedBox(height: 4),
            Text(
              'Connected region: ${fallbackServer.name}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
          if (regionLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              regionLabel,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  String? _regionGroupLabel(String group) => switch (group) {
        'europe' => 'Using European fallback',
        'north_america' => 'Using North American fallback',
        'asia_pacific' => 'Using Asia Pacific fallback',
        'south_america' => 'Using South American fallback',
        _ => null,
      };
}

// ── Server health banner ─────────────────────────────────────────────────────

class _ServerHealthBanner extends StatelessWidget {
  const _ServerHealthBanner({
    required this.servers,
    required this.vpnState,
  });

  final List<ServerRegion> servers;
  final VpnState vpnState;

  @override
  Widget build(BuildContext context) {
    if (servers.isEmpty) return const SizedBox.shrink();

    final allDown = servers.every((s) => s.regionHealthStatus == 'down');
    if (allDown) {
      return const _Banner(
        color: AppColors.errorLight,
        text: 'No servers available',
      );
    }

    final selectedId = vpnState.selectedServerId;
    if (selectedId != null) {
      for (final s in servers) {
        if (s.id == selectedId && s.regionHealthStatus == 'down') {
          return const _Banner(
            color: AppColors.warningLight,
            text: 'Selected region is offline',
          );
        }
      }
    }

    return const SizedBox.shrink();
  }
}

// ── Optimisation hint ────────────────────────────────────────────────────────

class _OptimisationHint extends StatelessWidget {
  const _OptimisationHint({required this.servers, required this.vpnState});

  final List<ServerRegion> servers;
  final VpnState vpnState;

  static const _hints = <String, String>{
    'north_america': 'Optimized for Caribbean routing',
    'europe': 'Optimized for transatlantic routing',
  };

  @override
  Widget build(BuildContext context) {
    final selectedId = vpnState.selectedServerId;
    if (selectedId == null) return const SizedBox.shrink();

    for (final s in servers) {
      if (s.id == selectedId) {
        final hint = _hints[s.regionGroup ?? ''];
        if (hint != null) {
          return _Banner(color: AppColors.primaryGhost, text: hint);
        }
        return const SizedBox.shrink();
      }
    }
    return const SizedBox.shrink();
  }
}

// ── Shared banner ────────────────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.space3),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space2,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/server_region.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../design/app_colors.dart';
import '../design/app_spacing.dart';
import '../widgets/empty_state.dart';
import '../widgets/ui_helpers.dart';
import '../widgets/vpn_ui_bindings.dart';

/// Server / location selection screen.
class ServerSelectionScreen extends ConsumerStatefulWidget {
  const ServerSelectionScreen({super.key});

  @override
  ConsumerState<ServerSelectionScreen> createState() =>
      _ServerSelectionScreenState();
}

class _ServerSelectionScreenState
    extends ConsumerState<ServerSelectionScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final serversAsync = ref.watch(serversProvider);
    final userPlanAsync = ref.watch(userPlanProvider);
    final vpnState = ref.watch(vpnStateProvider);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= AppSpacing.tabletBreakpoint;
    final planTier =
        userPlanAsync.valueOrNull?.isPremium == true ? 'premium' : 'free';
    final liveSwitching = ref.watch(connectionSupportsLiveSwitchProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servers'),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              0,
              AppSpacing.pagePadding,
              AppSpacing.space3,
            ),
            child: TextField(
              onChanged: (value) => setState(() => _query = value.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search servers, cities, or countries',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusFull),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: serversAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load servers',
          message: error.toString(),
          action: EmptyStateAction(
            label: 'Retry',
            onTap: () => ref.invalidate(serversProvider),
          ),
        ),
        data: (servers) {
          final filtered = _filterServers(servers, _query);
          if (filtered.isEmpty) {
            return const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No results',
              message: 'Try another location or protocol keyword.',
            );
          }

          final grouped = _groupByRegion(filtered);

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isWide ? AppSpacing.contentMaxWidth * 1.55 : 760,
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  AppSpacing.space3,
                  AppSpacing.pagePadding,
                  AppSpacing.space6,
                ),
                children: [
                  _SelectionBanner(
                    selectedServerId: vpnState.selectedServerId,
                    liveSwitching: liveSwitching,
                  ),
                  const SizedBox(height: AppSpacing.space4),
                  for (final entry in grouped.entries) ...[
                    _RegionHeader(region: entry.key, count: entry.value.length),
                    if (isWide)
                      _ResponsiveGrid(
                        servers: entry.value,
                        selectedId: vpnState.selectedServerId,
                        planTier: planTier,
                        onSelect: (server) => _selectServer(server, vpnState),
                      )
                    else
                      ...entry.value.map(
                        (server) => _ServerListTile(
                          server: server,
                          isSelected: vpnState.selectedServerId == server.id,
                          enabled: server.selectableForPlan(planTier),
                          onTap: () => _selectServer(server, vpnState),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<ServerRegion> _filterServers(List<ServerRegion> servers, String query) {
    if (query.isEmpty) return servers;
    return servers.where((server) {
      final text = [
        server.name,
        server.city,
        server.country,
        server.region,
        ...server.supportedProtocols,
      ].whereType<String>().join(' ').toLowerCase();
      return text.contains(query);
    }).toList();
  }

  Map<String, List<ServerRegion>> _groupByRegion(List<ServerRegion> servers) {
    final grouped = <String, List<ServerRegion>>{};
    for (final server in servers) {
      final region = server.region ?? 'Other';
      grouped.putIfAbsent(region, () => <ServerRegion>[]).add(server);
    }
    return grouped;
  }

  Future<void> _selectServer(ServerRegion server, VpnState vpnState) async {
    final planTier =
        ref.read(userPlanProvider).valueOrNull?.isPremium == true ? 'premium' : 'free';
    if (!server.selectableForPlan(planTier)) return;

    final notifier = ref.read(vpnStateProvider.notifier);
    final visualState = ref.read(connectionVisualStateProvider);
    final liveSwitching = connectionVisualStateSupportsLiveSwitch(visualState);

    if (liveSwitching) {
      await notifier.switchServer(server.id);
      return;
    }
    notifier.selectServer(server.id);
  }
}

class _SelectionBanner extends StatelessWidget {
  const _SelectionBanner({
    required this.selectedServerId,
    required this.liveSwitching,
  });

  final String? selectedServerId;
  final bool liveSwitching;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            liveSwitching ? Icons.swap_horiz_rounded : Icons.public_rounded,
            color: AppColors.primaryBright,
          ),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedServerId == null || selectedServerId!.isEmpty
                      ? 'No server pinned'
                      : 'Current selection: $selectedServerId',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: AppSpacing.space1),
                Text(
                  liveSwitching
                      ? 'Selecting a new region now will use the reconnect-aware state machine.'
                      : 'Choose any available region to pin it for the next connect.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({
    required this.servers,
    required this.selectedId,
    required this.planTier,
    required this.onSelect,
  });

  final List<ServerRegion> servers;
  final String? selectedId;
  final String planTier;
  final ValueChanged<ServerRegion> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.space2,
        crossAxisSpacing: AppSpacing.space2,
        childAspectRatio: 2.35,
      ),
      itemCount: servers.length,
      itemBuilder: (context, index) {
        final server = servers[index];
        return _ServerListTile(
          server: server,
          isSelected: selectedId == server.id,
          enabled: server.selectableForPlan(planTier),
          onTap: () => onSelect(server),
        );
      },
    );
  }
}

class _RegionHeader extends StatelessWidget {
  const _RegionHeader({
    required this.region,
    required this.count,
  });

  final String region;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.space5,
        bottom: AppSpacing.space2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              region.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkInkSoft,
                  ),
            ),
          ),
          Text(
            '$count servers',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _ServerListTile extends StatelessWidget {
  const _ServerListTile({
    required this.server,
    required this.isSelected,
    required this.enabled,
    required this.onTap,
  });

  final ServerRegion server;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final flag = flagEmoji(server.countryCode);
    final latencyColor = _latencyColor(server.latencyMs);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final down = (server.regionHealthStatus ?? '').toLowerCase() == 'down';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space2),
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: Material(
          color: isSelected
              ? AppColors.primaryBright.withValues(alpha: 0.12)
              : (isDark
                  ? AppColors.darkSurface
                  : Theme.of(context).colorScheme.surface),
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space4,
                vertical: AppSpacing.space3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        flag.isNotEmpty ? flag : '🌐',
                        style: const TextStyle(fontSize: 22),
                      ),
                      const SizedBox(width: AppSpacing.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              server.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? AppColors.primaryBright
                                        : null,
                                  ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: AppSpacing.space1),
                            Text(
                              [
                                if (server.city != null) server.city!,
                                if (server.country != null) server.country!,
                              ].join(', '),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.darkInkSoft),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (!enabled)
                        const Icon(
                          Icons.lock_rounded,
                          color: AppColors.warning,
                          size: AppSpacing.iconS,
                        )
                      else if (isSelected)
                        const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.primaryBright,
                          size: AppSpacing.iconS,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  Wrap(
                    spacing: AppSpacing.space2,
                    runSpacing: AppSpacing.space2,
                    children: [
                      _InfoChip(
                        icon: down ? Icons.cloud_off_rounded : Icons.bolt_rounded,
                        label: down
                            ? 'Region down'
                            : server.regionHealthStatus?.toUpperCase() ?? 'UP',
                        color: down ? AppColors.error : AppColors.success,
                      ),
                      if (server.latencyMs != null)
                        _InfoChip(
                          icon: Icons.speed_rounded,
                          label: latencyLabel(server.latencyMs),
                          color: latencyColor,
                        ),
                      if (server.premiumOnly ||
                          server.tierRestriction?.toLowerCase() == 'premium')
                        const _InfoChip(
                          icon: Icons.workspace_premium_rounded,
                          label: 'Premium',
                          color: AppColors.secondaryDark,
                        ),
                      for (final protocol in server.supportedProtocols.take(3))
                        _InfoChip(
                          icon: Icons.shield_outlined,
                          label: protocol.toUpperCase(),
                          color: AppColors.primaryBright,
                        ),
                    ],
                  ),
                  if (!enabled) ...[
                    const SizedBox(height: AppSpacing.space3),
                    Text(
                      'Upgrade required to select this region.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _latencyColor(int? ms) {
    if (ms == null) return AppColors.darkInkSoft;
    if (ms <= 40) return AppColors.success;
    if (ms <= 100) return AppColors.warning;
    return AppColors.error;
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space2,
        vertical: AppSpacing.space1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSpacing.iconXS, color: color),
          const SizedBox(width: AppSpacing.space1),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

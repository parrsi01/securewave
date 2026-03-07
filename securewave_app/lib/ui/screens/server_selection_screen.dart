import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/server_region.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/widgets/ui_helpers.dart';
import '../../ui/widgets/empty_state.dart';

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
    final vpnState = ref.watch(vpnStateProvider);

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
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search servers…',
                prefixIcon: const Icon(Icons.search_rounded,
                    size: AppSpacing.iconS),
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
        error: (e, _) => EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load servers',
          message: e.toString(),
          action: EmptyStateAction(
            label: 'Retry',
            onTap: () => ref.invalidate(serversProvider),
          ),
        ),
        data: (servers) {
          final filtered = _query.isEmpty
              ? servers
              : servers
                  .where((s) =>
                      s.name.toLowerCase().contains(_query) ||
                      (s.city?.toLowerCase().contains(_query) ?? false) ||
                      (s.country?.toLowerCase().contains(_query) ?? false))
                  .toList();

          if (filtered.isEmpty) {
            return EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No results',
              message: 'Try a different search term.',
            );
          }

          // Group by region
          final grouped = <String, List<ServerRegion>>{};
          for (final s in filtered) {
            final region = s.region ?? 'Other';
            grouped.putIfAbsent(region, () => []).add(s);
          }

          return ListView.builder(
            padding: const EdgeInsets.only(
              left: AppSpacing.pagePadding,
              right: AppSpacing.pagePadding,
              bottom: AppSpacing.space6,
            ),
            itemCount: grouped.entries
                .fold<int>(0, (sum, e) => sum + e.value.length + 1),
            itemBuilder: (context, index) {
              // Flatten grouped map into a list of [header | server]
              final items = <Object>[];
              for (final entry in grouped.entries) {
                items.add(entry.key);
                items.addAll(entry.value);
              }

              final item = items[index];
              if (item is String) {
                return _RegionHeader(region: item);
              }
              final server = item as ServerRegion;
              final isSelected =
                  vpnState.selectedServerId == server.id;
              return _ServerListTile(
                server: server,
                isSelected: isSelected,
                onTap: () {
                  ref
                      .read(vpnStateProvider.notifier)
                      .selectServer(server.id);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _RegionHeader extends StatelessWidget {
  const _RegionHeader({required this.region});
  final String region;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.space5,
        bottom: AppSpacing.space2,
      ),
      child: Text(
        region.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: AppColors.inkSoft,
            ),
      ),
    );
  }
}

class _ServerListTile extends StatelessWidget {
  const _ServerListTile({
    required this.server,
    required this.isSelected,
    required this.onTap,
  });

  final ServerRegion server;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final flag = flagEmoji(server.countryCode);
    final latencyColor = _latencyColor(server.latencyMs);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space2),
      child: Material(
        color: isSelected
            ? AppColors.primaryLight
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space4,
              vertical: AppSpacing.space3,
            ),
            child: Row(
              children: [
                Text(
                  flag.isNotEmpty ? flag : '🌐',
                  style: const TextStyle(fontSize: 22),
                ),
                const SizedBox(width: AppSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                            ),
                      ),
                      if (server.city != null)
                        Text(
                          server.city!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.inkSoft),
                        ),
                    ],
                  ),
                ),
                // Premium badge
                if (server.premiumOnly ||
                    server.tierRestriction == 'premium')
                  Container(
                    margin: const EdgeInsets.only(right: AppSpacing.space2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryDark,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusFull),
                    ),
                    child: const Text(
                      'PRO',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                // Latency pill
                if (server.latencyMs != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: latencyColor.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusFull),
                    ),
                    child: Text(
                      '${server.latencyMs} ms',
                      style: TextStyle(
                        fontSize: 11,
                        color: latencyColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (isSelected) ...[
                  const SizedBox(width: AppSpacing.space2),
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.primary, size: AppSpacing.iconS),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _latencyColor(int? ms) {
    if (ms == null) return AppColors.inkSoft;
    if (ms <= 40) return AppColors.success;
    if (ms <= 100) return AppColors.warning;
    return AppColors.error;
  }
}

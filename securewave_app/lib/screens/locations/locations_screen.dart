import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/server_region.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/design/app_animations.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import 'widgets/server_tile.dart';

enum _Filter { all, favorites, recommended }

/// Locations screen — v2.
///
/// Card-grouped server list with a modern search bar,
/// animated filter chips, and smooth expand/collapse regions.
class LocationsScreen extends ConsumerStatefulWidget {
  const LocationsScreen({super.key});

  @override
  ConsumerState<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends ConsumerState<LocationsScreen> {
  _Filter _filter = _Filter.all;
  String _search = '';
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) setState(() => _search = value.toLowerCase());
    });
  }

  String _regionOf(ServerRegion server) {
    final raw = server.region?.trim();
    if (raw == null || raw.isEmpty) return 'Other';
    return raw;
  }

  List<ServerRegion> _applyFilters(List<ServerRegion> all) {
    final favorites = ref.read(favoriteServersProvider);
    var list = all;

    if (_filter == _Filter.favorites) {
      list = list.where((s) => favorites.contains(s.id)).toList();
    } else if (_filter == _Filter.recommended) {
      list = list.where((s) => s.latencyMs != null).toList()
        ..sort((a, b) => (a.latencyMs ?? 999).compareTo(b.latencyMs ?? 999));
      list = list.take(5).toList();
    }

    if (_search.isNotEmpty) {
      list = list
          .where((s) =>
              s.name.toLowerCase().contains(_search) ||
              (s.city?.toLowerCase().contains(_search) ?? false) ||
              (s.country?.toLowerCase().contains(_search) ?? false))
          .toList();
    }

    return list;
  }

  Map<String, List<ServerRegion>> _groupByRegion(List<ServerRegion> servers) {
    final groups = <String, List<ServerRegion>>{};
    for (final s in servers) {
      final region = _regionOf(s);
      (groups[region] ??= []).add(s);
    }
    for (final entry in groups.entries) {
      entry.value.sort((a, b) {
        final priorityCmp =
            (a.latencyPriority ?? 9999).compareTo(b.latencyPriority ?? 9999);
        if (priorityCmp != 0) return priorityCmp;
        final latencyCmp = (a.latencyMs ?? 9999).compareTo(b.latencyMs ?? 9999);
        if (latencyCmp != 0) return latencyCmp;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final serversAsync = ref.watch(serversProvider);
    final selectedId =
        ref.watch(vpnStateProvider.select((s) => s.selectedServerId));
    final favorites = ref.watch(favoriteServersProvider);
    final borderColor = isDark ? AppColors.darkBorder : AppColors.border;

    return Column(
      children: [
        // ── Search bar ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.space4,
            AppSpacing.space4,
            AppSpacing.space4,
            AppSpacing.space2,
          ),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by country, city or server…',
              prefixIcon: Icon(
                Icons.search_rounded,
                size: AppSpacing.iconS,
                color: isDark ? AppColors.darkInkSoft : AppColors.inkSoft,
              ),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close_rounded,
                          size: AppSpacing.iconXS,
                          color: isDark
                              ? AppColors.darkInkSoft
                              : AppColors.inkSoft),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _search = '');
                      },
                    )
                  : null,
              isDense: false,
            ),
            onChanged: _onSearch,
          ),
        ),

        // ── Filter chips ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space4,
            vertical: AppSpacing.space1,
          ),
          child: Row(
            children: _Filter.values.map((f) {
              final label = switch (f) {
                _Filter.all => 'All',
                _Filter.favorites => 'Favorites',
                _Filter.recommended => 'Fastest',
              };
              final selected = _filter == f;
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.space2),
                child: AnimatedContainer(
                  duration: AppAnimations.durationFast,
                  child: FilterChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (_) => setState(() => _filter = f),
                    showCheckmark: false,
                    side: BorderSide(
                      color: selected
                          ? (isDark
                              ? AppColors.primaryBright
                              : AppColors.primary)
                          : borderColor,
                    ),
                    labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? (isDark
                                  ? AppColors.primaryBright
                                  : AppColors.primary)
                              : null,
                        ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: AppSpacing.space2),

        // ── Server list ────────────────────────────────────────────────
        Expanded(
          child: serversAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(strokeCap: StrokeCap.round),
            ),
            error: (e, _) => _buildError(context, e, isDark),
            data: (allServers) {
              final filtered = _applyFilters(allServers);

              if (filtered.isEmpty) {
                return _buildEmpty(context, isDark);
              }

              final groups = _groupByRegion(filtered);
              final orderedKeys = groups.keys.toList()
                ..sort((a, b) {
                  final aMin = groups[a]!
                      .map((s) => s.latencyPriority ?? 9999)
                      .fold<int>(
                          9999, (prev, next) => next < prev ? next : prev);
                  final bMin = groups[b]!
                      .map((s) => s.latencyPriority ?? 9999)
                      .fold<int>(
                          9999, (prev, next) => next < prev ? next : prev);
                  final priorityCmp = aMin.compareTo(bMin);
                  if (priorityCmp != 0) return priorityCmp;
                  return a.toLowerCase().compareTo(b.toLowerCase());
                });

              return RefreshIndicator(
                color: isDark ? AppColors.primaryBright : AppColors.primary,
                onRefresh: () async => ref.refresh(serversProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.space4,
                    0,
                    AppSpacing.space4,
                    AppSpacing.space8,
                  ),
                  itemCount: orderedKeys.length,
                  itemBuilder: (context, i) {
                    final region = orderedKeys[i];
                    final servers = groups[region]!;
                    return _RegionCard(
                      region: region,
                      servers: servers,
                      selectedId: selectedId,
                      favorites: favorites,
                      initiallyExpanded: i == 0,
                      onSelect: (serverId) {
                        unawaited(
                          ref
                              .read(vpnStateProvider.notifier)
                              .switchServer(serverId),
                        );
                        context.go('/home');
                      },
                      onToggleFavorite: (serverId) => ref
                          .read(favoriteServersProvider.notifier)
                          .toggle(serverId),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context, Object e, bool isDark) {
    final isAuthError = e is DioException &&
        (e.response?.statusCode == 401 || e.response?.statusCode == 403);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAuthError
                  ? Icons.lock_outline_rounded
                  : Icons.cloud_off_rounded,
              size: 56,
              color: isDark ? AppColors.darkInkSoft : AppColors.inkSoft,
            ),
            const SizedBox(height: AppSpacing.space4),
            Text(
              isAuthError
                  ? 'Sign in to view servers'
                  : 'Could not load servers',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (isAuthError) ...[
              const SizedBox(height: AppSpacing.space2),
              Text(
                'Server locations require an active account.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: AppSpacing.space5),
            FilledButton.icon(
              onPressed: () => isAuthError
                  ? context.go('/login')
                  : ref.refresh(serversProvider),
              icon: Icon(isAuthError ? Icons.login : Icons.refresh,
                  size: AppSpacing.iconXS),
              label: Text(isAuthError ? 'Sign In' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 56,
            color: isDark ? AppColors.darkInkSoft : AppColors.inkSoft,
          ),
          const SizedBox(height: AppSpacing.space4),
          Text(
            'No servers match',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            'Try adjusting your search or filter.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ── Region card ────────────────────────────────────────────────────────────

class _RegionCard extends StatelessWidget {
  const _RegionCard({
    required this.region,
    required this.servers,
    required this.selectedId,
    required this.favorites,
    required this.initiallyExpanded,
    required this.onSelect,
    required this.onToggleFavorite,
  });

  final String region;
  final List<ServerRegion> servers;
  final String? selectedId;
  final Set<String> favorites;
  final bool initiallyExpanded;
  final void Function(String serverId) onSelect;
  final void Function(String serverId) onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space3),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXXL),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.border,
            width: 0.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXXL),
          child: Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
            child: ExpansionTile(
              initiallyExpanded: initiallyExpanded,
              tilePadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space5,
                vertical: AppSpacing.space2,
              ),
              title: Row(
                children: [
                  Text(
                    region,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.space2,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceMuted
                          : AppColors.surfaceMuted,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusFull),
                    ),
                    child: Text(
                      '${servers.length}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              children: [
                Divider(
                  height: 1,
                  thickness: 0.5,
                  color: isDark ? AppColors.darkBorder : AppColors.border,
                ),
                ...servers.map((s) => ServerTile(
                      server: s,
                      isSelected: s.id == selectedId,
                      isFavorite: favorites.contains(s.id),
                      onTap: () => onSelect(s.id),
                      onToggleFavorite: () => onToggleFavorite(s.id),
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

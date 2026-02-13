import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/server_region.dart';
import '../../core/state/vpn_state.dart';
import '../../services/api_client.dart';
import '../../ui/design/app_animations.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import 'widgets/location_list_item.dart';
import 'widgets/location_search_bar.dart';

/// Filter options for the locations list.
enum _LocationFilter { all, favorites, recommended }

/// Phase 3 rebuild of the server-locations screen.
///
/// Fetches servers from the API, supports search, filter chips
/// (All / Favorites / Recommended), pull-to-refresh, and
/// loading / error / empty states.
class LocationsScreen extends ConsumerStatefulWidget {
  const LocationsScreen({super.key});

  @override
  ConsumerState<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends ConsumerState<LocationsScreen> {
  List<ServerRegion>? _servers;
  Object? _error;
  bool _isLoading = true;

  String _searchQuery = '';
  _LocationFilter _activeFilter = _LocationFilter.all;
  final Set<String> _favorites = {};

  @override
  void initState() {
    super.initState();
    _loadServers();
  }

  Future<void> _loadServers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final servers = await api.fetchServers(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _servers = servers;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query.toLowerCase());
  }

  void _onFilterChanged(_LocationFilter filter) {
    setState(() => _activeFilter = filter);
  }

  void _toggleFavorite(String serverId) {
    setState(() {
      if (_favorites.contains(serverId)) {
        _favorites.remove(serverId);
      } else {
        _favorites.add(serverId);
      }
    });
  }

  void _selectServer(String serverId) {
    ref.read(vpnStateProvider.notifier).selectServer(serverId);
    context.go('/vpn');
  }

  List<ServerRegion> get _filteredServers {
    if (_servers == null) return [];
    var list = _servers!;

    // Apply filter
    switch (_activeFilter) {
      case _LocationFilter.favorites:
        list = list.where((s) => _favorites.contains(s.id)).toList();
      case _LocationFilter.recommended:
        // Recommended = latency < 80ms (or unknown latency, show all)
        list = list
            .where((s) => s.latencyMs == null || s.latencyMs! < 80)
            .toList();
      case _LocationFilter.all:
        break;
    }

    // Apply search
    if (_searchQuery.isNotEmpty) {
      list = list.where((s) {
        final name = s.name.toLowerCase();
        final country = (s.country ?? '').toLowerCase();
        final city = (s.city ?? '').toLowerCase();
        return name.contains(_searchQuery) ||
            country.contains(_searchQuery) ||
            city.contains(_searchQuery);
      }).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final selectedServerId = ref.watch(
      vpnStateProvider.select((s) => s.selectedServerId),
    );

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // -- Header
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space5,
                  AppSpacing.space5,
                  AppSpacing.space5,
                  AppSpacing.space3,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Locations',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.space2),
                    Text(
                      'Choose a server to route your traffic through.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.inkMuted,
                          ),
                    ),
                  ],
                ),
              ),

              // -- Search bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space5,
                ),
                child: LocationSearchBar(onChanged: _onSearchChanged),
              ),
              const SizedBox(height: AppSpacing.space3),

              // -- Filter chips
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space5,
                ),
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'All',
                      isActive: _activeFilter == _LocationFilter.all,
                      onTap: () => _onFilterChanged(_LocationFilter.all),
                    ),
                    const SizedBox(width: AppSpacing.space2),
                    _FilterChip(
                      label: 'Favorites',
                      isActive: _activeFilter == _LocationFilter.favorites,
                      onTap: () => _onFilterChanged(_LocationFilter.favorites),
                    ),
                    const SizedBox(width: AppSpacing.space2),
                    _FilterChip(
                      label: 'Recommended',
                      isActive: _activeFilter == _LocationFilter.recommended,
                      onTap: () =>
                          _onFilterChanged(_LocationFilter.recommended),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space3),

              // -- Content area
              Expanded(child: _buildContent(selectedServerId)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(String? selectedServerId) {
    // Loading state
    if (_isLoading) {
      return _buildSkeletonList();
    }

    // Error state
    if (_error != null) {
      return _buildErrorState();
    }

    final filtered = _filteredServers;

    // Empty state
    if (filtered.isEmpty) {
      return _buildEmptyState();
    }

    // Server list
    return RefreshIndicator(
      onRefresh: _loadServers,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final server = filtered[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.space2),
            child: LocationListItem(
              server: server,
              isSelected: server.id == selectedServerId,
              isFavorite: _favorites.contains(server.id),
              onTap: () => _selectServer(server.id),
              onToggleFavorite: () => _toggleFavorite(server.id),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.space2),
          child: AnimatedOpacity(
            opacity: 0.5,
            duration: AppAnimations.durationSlow,
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppSpacing.radiusL),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: AppColors.inkSoft,
            ),
            const SizedBox(height: AppSpacing.space4),
            Text(
              'Unable to load locations',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              'Check your connection and try again.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.inkMuted,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.space5),
            FilledButton.icon(
              onPressed: _loadServers,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isFiltered =
        _searchQuery.isNotEmpty || _activeFilter != _LocationFilter.all;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFiltered ? Icons.filter_list_off : Icons.public_off,
              size: 48,
              color: AppColors.inkSoft,
            ),
            const SizedBox(height: AppSpacing.space4),
            Text(
              isFiltered ? 'No matching locations' : 'No locations available',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(
              isFiltered
                  ? 'Try a different search term or filter.'
                  : 'Locations will appear once servers come online.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.inkMuted,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single filter chip used in the filter row.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppAnimations.durationFast,
        curve: AppAnimations.curveDefault,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space3,
          vertical: AppSpacing.space2,
        ),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: isActive ? Colors.white : AppColors.inkMuted,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
        ),
      ),
    );
  }
}

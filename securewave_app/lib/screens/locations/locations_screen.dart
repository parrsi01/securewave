import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/server_region.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import 'widgets/server_tile.dart';

enum _Filter { all, favorites, recommended }

class LocationsScreen extends ConsumerStatefulWidget {
  const LocationsScreen({super.key});

  @override
  ConsumerState<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends ConsumerState<LocationsScreen> {
  _Filter _filter = _Filter.all;
  String _search = '';
  Timer? _debounce;

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _search = value.toLowerCase());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  static const _regionMap = <String, List<String>>{
    'Europe': ['Germany', 'Netherlands', 'United Kingdom', 'France', 'Sweden', 'Switzerland', 'Austria', 'Poland', 'Norway', 'Finland', 'Denmark', 'Belgium', 'Czech Republic', 'Portugal', 'Romania', 'Italy', 'Spain', 'Ireland', 'Ukraine'],
    'Americas': ['United States', 'Canada', 'Brazil', 'Mexico', 'Argentina', 'Chile'],
    'Asia-Pacific': ['Japan', 'Singapore', 'Australia', 'South Korea', 'India', 'Hong Kong', 'Taiwan', 'New Zealand'],
    'Middle East & Africa': ['Israel', 'Turkey', 'South Africa', 'United Arab Emirates'],
  };

  String _regionOf(String? country) {
    if (country == null) return 'Other';
    for (final e in _regionMap.entries) {
      if (e.value.contains(country)) return e.key;
    }
    return 'Other';
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
      list = list.where((s) =>
          s.name.toLowerCase().contains(_search) ||
          (s.city?.toLowerCase().contains(_search) ?? false) ||
          (s.country?.toLowerCase().contains(_search) ?? false)).toList();
    }

    return list;
  }

  Map<String, List<ServerRegion>> _groupByRegion(List<ServerRegion> servers) {
    final groups = <String, List<ServerRegion>>{};
    for (final s in servers) {
      final region = _regionOf(s.country);
      (groups[region] ??= []).add(s);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final serversAsync = ref.watch(serversProvider);
    final selectedId = ref.watch(vpnStateProvider.select((s) => s.selectedServerId));
    final favorites = ref.watch(favoriteServersProvider);

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.space4, AppSpacing.space4, AppSpacing.space4, AppSpacing.space2),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search servers...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() => _search = ''))
                  : null,
              isDense: true,
            ),
            onChanged: _onSearch,
          ),
        ),
        // Filter chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
          child: Row(
            children: _Filter.values.map((f) {
              final label = switch (f) { _Filter.all => 'All', _Filter.favorites => 'Favorites', _Filter.recommended => 'Recommended' };
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.space2),
                child: ChoiceChip(
                  label: Text(label),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: AppSpacing.space2),
        // Server list
        Expanded(
          child: serversAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.inkSoft),
                  const SizedBox(height: AppSpacing.space3),
                  Text('Could not load servers', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: AppSpacing.space3),
                  FilledButton(onPressed: () => ref.refresh(serversProvider), child: const Text('Retry')),
                ],
              ),
            ),
            data: (allServers) {
              final filtered = _applyFilters(allServers);
              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.filter_list_off_rounded, size: 48, color: AppColors.inkSoft),
                      const SizedBox(height: AppSpacing.space3),
                      Text('No servers match', style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                );
              }

              final groups = _groupByRegion(filtered);
              final regionOrder = ['Europe', 'Americas', 'Asia-Pacific', 'Middle East & Africa', 'Other'];
              final orderedKeys = regionOrder.where(groups.containsKey).toList();

              return RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async => ref.refresh(serversProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: AppSpacing.space8),
                  itemCount: orderedKeys.length,
                  itemBuilder: (context, i) {
                    final region = orderedKeys[i];
                    final servers = groups[region]!;
                    return ExpansionTile(
                      title: Text('$region (${servers.length})', style: Theme.of(context).textTheme.titleSmall),
                      initiallyExpanded: i == 0,
                      children: servers.map((s) => ServerTile(
                        server: s,
                        isSelected: s.id == selectedId,
                        isFavorite: favorites.contains(s.id),
                        onTap: () {
                          ref.read(vpnStateProvider.notifier).selectServer(s.id);
                          context.go('/home');
                        },
                        onToggleFavorite: () => ref.read(favoriteServersProvider.notifier).toggle(s.id),
                      )).toList(),
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
}

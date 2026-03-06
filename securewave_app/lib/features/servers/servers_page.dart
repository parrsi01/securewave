import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/server_region.dart';
import '../../core/optimization/marlxgb.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/components/dashboard_card.dart';
import '../../ui/components/section_container.dart';
import '../../ui/components/server_card.dart';
import '../../ui/layout/adaptive_shell_scaffold.dart';
import '../../ui/theme/spacing.dart';

class ServersPage extends ConsumerStatefulWidget {
  const ServersPage({super.key});

  @override
  ConsumerState<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends ConsumerState<ServersPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(serversProvider);
    final vpnState = ref.watch(vpnStateProvider);
    final favorites = ref.watch(favoriteServersProvider);
    const predictor = MarLXGBPredictor();

    return AdaptiveShellScaffold(
      child: servers.when(
        data: (data) {
          final query = _searchController.text.trim().toLowerCase();
          final filtered = data.where((server) {
            if (query.isEmpty) {
              return true;
            }
            final haystack =
                '${server.name} ${server.country ?? ''} ${server.city ?? ''}'
                    .toLowerCase();
            return haystack.contains(query);
          }).toList()
            ..sort((a, b) {
              final aScore = predictor.scoreServer(a,
                  isFavorite: favorites.contains(a.id));
              final bScore = predictor.scoreServer(b,
                  isFavorite: favorites.contains(b.id));
              return bScore.compareTo(aScore);
            });

          final favoritesFirst =
              filtered.where((s) => favorites.contains(s.id));
          final grouped = <String, List<ServerRegion>>{};
          for (final server in filtered) {
            final key = server.country ?? server.name;
            grouped.putIfAbsent(key, () => <ServerRegion>[]).add(server);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionContainer(
                title: 'Server browser',
                subtitle:
                    'Search, favorite, and browse by country without stretching desktop layouts.',
                child: DashboardCard(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Search by country, city, or location',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: SecureWaveSpacing.xl),
              if (favoritesFirst.isNotEmpty)
                _ServerGroup(
                  title: 'Favorites',
                  servers: favoritesFirst.toList(growable: false),
                  selectedServerId: vpnState.selectedServerId,
                  favorites: favorites,
                  onSelect: (serverId) => ref
                      .read(vpnStateProvider.notifier)
                      .selectServer(serverId),
                  onToggleFavorite: (serverId) => ref
                      .read(favoriteServersProvider.notifier)
                      .toggle(serverId),
                ),
              for (final entry in grouped.entries) ...[
                if (favoritesFirst.isNotEmpty || entry.key != 'Favorites') ...[
                  if (favoritesFirst.isNotEmpty ||
                      entry != grouped.entries.first)
                    const SizedBox(height: SecureWaveSpacing.xl),
                  _ServerGroup(
                    title: entry.key,
                    servers: entry.value,
                    selectedServerId: vpnState.selectedServerId,
                    favorites: favorites,
                    onSelect: (serverId) => ref
                        .read(vpnStateProvider.notifier)
                        .selectServer(serverId),
                    onToggleFavorite: (serverId) => ref
                        .read(favoriteServersProvider.notifier)
                        .toggle(serverId),
                  ),
                ],
              ],
              if (filtered.isEmpty) ...[
                const SizedBox(height: SecureWaveSpacing.xl),
                const DashboardCard(
                  child: Text('No servers match the current search.'),
                ),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => DashboardCard(
          child: Text('Unable to load servers: $error'),
        ),
      ),
    );
  }
}

class _ServerGroup extends StatelessWidget {
  const _ServerGroup({
    required this.title,
    required this.servers,
    required this.selectedServerId,
    required this.favorites,
    required this.onSelect,
    required this.onToggleFavorite,
  });

  final String title;
  final List<ServerRegion> servers;
  final String? selectedServerId;
  final Set<String> favorites;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return SectionContainer(
      title: title,
      subtitle: '${servers.length} available locations',
      child: Column(
        children: [
          for (var index = 0; index < servers.length; index++) ...[
            ServerCard(
              server: servers[index],
              isSelected: servers[index].id == selectedServerId,
              isFavorite: favorites.contains(servers[index].id),
              onTap: () => onSelect(servers[index].id),
              onToggleFavorite: () => onToggleFavorite(servers[index].id),
            ),
            if (index != servers.length - 1)
              const SizedBox(height: SecureWaveSpacing.md),
          ],
        ],
      ),
    );
  }
}

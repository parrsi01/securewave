import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../components/server_card.dart';
import '../layout/page_frame.dart';
import '../theme/securewave_theme.dart';
import '../widgets/glass_panel.dart';

class ServerSelectionScreen extends HookConsumerWidget {
  const ServerSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchController = useTextEditingController();
    final query = useState('');
    final favoritesOnly = useState(false);
    final servers = ref.watch(serversProvider);
    final favorites = ref.watch(favoriteServersProvider);
    final selectedId =
        ref.watch(vpnStateProvider.select((state) => state.selectedServerId));
    final plan = ref.watch(userPlanProvider).valueOrNull;

    return PageFrame(
      eyebrow: 'Servers',
      title: 'Server selection',
      subtitle:
          'Search, filter, and browse regions in grouped lists with latency and load surfaced first.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search by country, city, or region id',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (value) =>
                      query.value = value.trim().toLowerCase(),
                ),
                const SizedBox(height: SecureWaveSpacing.spaceSM),
                Wrap(
                  spacing: SecureWaveSpacing.spaceXS,
                  runSpacing: SecureWaveSpacing.spaceXS,
                  children: <Widget>[
                    FilterChip(
                      label: const Text('All regions'),
                      selected: !favoritesOnly.value,
                      onSelected: (_) => favoritesOnly.value = false,
                    ),
                    FilterChip(
                      label: const Text('Favorites'),
                      selected: favoritesOnly.value,
                      onSelected: (_) => favoritesOnly.value = true,
                    ),
                    if (selectedId != null && selectedId.isNotEmpty)
                      FilterChip(
                        label: Text('Selected: $selectedId'),
                        selected: true,
                        onSelected: (_) {},
                      ),
                  ],
                ),
                const SizedBox(height: SecureWaveSpacing.spaceSM),
                Text(
                  'Regions are grouped by country or backend region group for faster scanning.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ).animate().fadeIn(duration: 260.ms).slideY(begin: 0.05),
          const SizedBox(height: SecureWaveSpacing.spaceSM),
          servers.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
            error: (error, _) => _ServerError(error: error),
            data: (items) {
              final filtered = items.where((server) {
                if (favoritesOnly.value && !favorites.contains(server.id)) {
                  return false;
                }
                if (query.value.isEmpty) return true;
                final haystack = <String>[
                  server.id,
                  server.name,
                  server.country ?? '',
                  server.city ?? '',
                ].join(' ').toLowerCase();
                return haystack.contains(query.value);
              }).toList()
                ..sort((a, b) {
                  final aLatency = a.latencyMs ?? 9999;
                  final bLatency = b.latencyMs ?? 9999;
                  return aLatency.compareTo(bLatency);
                });

              if (filtered.isEmpty) {
                return GlassPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'No matching regions',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Adjust the search term or favorites filter to see more regions.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                );
              }

              final grouped = <String, List<dynamic>>{};
              for (final server in filtered) {
                final groupName = (server.country ??
                        server.regionGroup ??
                        server.region ??
                        'Other regions')
                    .trim();
                grouped.putIfAbsent(groupName, () => <dynamic>[]).add(server);
              }
              final groupNames = grouped.keys.toList(growable: false)..sort();

              return Column(
                children: groupNames.asMap().entries.map((entry) {
                  final groupIndex = entry.key;
                  final groupName = entry.value;
                  final serversInGroup = grouped[groupName]!.cast<dynamic>();
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: groupIndex == groupNames.length - 1
                          ? 0
                          : SecureWaveSpacing.spaceSM,
                    ),
                    child: GlassPanel(
                      padding: const EdgeInsets.all(SecureWaveSpacing.spaceSM),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  groupName,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              Text(
                                '${serversInGroup.length} regions',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: SecureWaveSpacing.spaceSM),
                          ...serversInGroup.asMap().entries.map((serverEntry) {
                            final server = serverEntry.value as dynamic;
                            final enabled = server.selectableForPlan(plan?.name);
                            return ServerCard(
                              server: server,
                              isSelected: selectedId == server.id,
                              isFavorite: favorites.contains(server.id),
                              enabled: enabled,
                              disabledReason:
                                  enabled ? null : 'Premium plan required',
                              onTap: () async {
                                await ref
                                    .read(vpnStateProvider.notifier)
                                    .switchServer(server.id);
                                if (!context.mounted) return;
                                context.go('/home');
                              },
                              onToggleFavorite: () => ref
                                  .read(favoriteServersProvider.notifier)
                                  .toggle(server.id),
                            )
                                .animate()
                                .fadeIn(
                                  duration: 220.ms,
                                  delay:
                                      ((groupIndex * 70) + (serverEntry.key * 24))
                                          .ms,
                                )
                                .slideY(begin: 0.03);
                          }),
                        ],
                      ),
                    ),
                  );
                }).toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ServerError extends ConsumerWidget {
  const _ServerError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dio = error is DioException ? error as DioException : null;
    final authError = dio != null &&
        (dio.response?.statusCode == 401 || dio.response?.statusCode == 403);
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            authError ? 'Sign in required' : 'Unable to load servers',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Text(
            authError
                ? 'The current session cannot access the region catalog.'
                : 'Refresh the catalog or open diagnostics for backend detail.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => ref.invalidate(serversProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

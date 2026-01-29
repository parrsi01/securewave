import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/optimization/marlxgb.dart';
import '../../core/state/app_state.dart';
import '../../ui/app_ui_v1.dart';
import '../../core/state/vpn_state.dart';

class ServersPage extends ConsumerWidget {
  const ServersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final vpnState = ref.watch(vpnStateProvider);
    final favorites = ref.watch(favoriteServersProvider);
    const predictor = MarLXGBPredictor();

    return SafeArea(
      child: servers.when(
        data: (data) {
          if (data.isNotEmpty && vpnState.selectedServerId == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(vpnStateProvider.notifier).selectServer(data.first.id);
            });
          }
          final sorted = List.of(data);
          sorted.sort((a, b) {
            final aScore =
                predictor.scoreServer(a, isFavorite: favorites.contains(a.id));
            final bScore =
                predictor.scoreServer(b, isFavorite: favorites.contains(b.id));
            return bScore.compareTo(aScore);
          });

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(AppUIv1.space5),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Choose a region', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: AppUIv1.space2),
                      Text(
                        'SecureWave will use this region whenever you connect.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppUIv1.space4),
                      if (sorted.isEmpty)
                        const Text('No regions are available right now.'),
                    ],
                  ),
                ),
              ),
              if (sorted.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: AppUIv1.space5),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final server = sorted[index];
                        final isSelected = server.id == vpnState.selectedServerId;
                        final isFavorite = favorites.contains(server.id);
                        final latencyLabel =
                            server.latencyMs == null ? '-- ms' : '${server.latencyMs} ms';
                        final subtitleParts = <String>[];
                        if (server.country != null && server.country!.isNotEmpty) {
                          subtitleParts.add(server.country!);
                        }
                        subtitleParts.add('Latency $latencyLabel');
                        final subtitle = subtitleParts.join(' • ');
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppUIv1.space3),
                          child: Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(color: isSelected ? AppUIv1.accent : AppUIv1.border),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(AppUIv1.space4),
                              leading: CircleAvatar(
                                backgroundColor:
                                    isSelected ? AppUIv1.accentSoft : AppUIv1.surfaceMuted,
                                child: Icon(
                                  Icons.public,
                                  color: isSelected ? AppUIv1.accentStrong : AppUIv1.inkSoft,
                                ),
                              ),
                              title: Text(server.name, style: Theme.of(context).textTheme.titleMedium),
                              subtitle: Text(
                                isSelected ? 'Selected for next connection • $subtitle' : subtitle,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: isFavorite ? 'Remove favorite' : 'Mark favorite',
                                    icon: Icon(isFavorite ? Icons.star : Icons.star_border),
                                    color: isFavorite ? AppUIv1.accentSun : AppUIv1.inkSoft,
                                    onPressed: () => ref
                                        .read(favoriteServersProvider.notifier)
                                        .toggle(server.id),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.check_circle, color: AppUIv1.accent)
                                  else
                                    const Icon(Icons.chevron_right),
                                ],
                              ),
                              onTap: () =>
                                  ref.read(vpnStateProvider.notifier).selectServer(server.id),
                            ),
                          ),
                        );
                      },
                      childCount: sorted.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: AppUIv1.space5)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Text('Unable to load regions. Please try again.'),
      ),
    );
  }
}

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
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppUIv1.contentMaxWidth),
          child: servers.when(
            data: (data) {
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
                          Text('Choose a region',
                              style: Theme.of(context).textTheme.titleLarge),
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
                    padding:
                          const EdgeInsets.symmetric(horizontal: AppUIv1.space5),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            if (index == 0) {
                              final isSelected = vpnState.selectedServerId == null;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: AppUIv1.space3),
                                child: AnimatedContainer(
                                  duration: AppUIv1.durationFast,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(AppUIv1.radiusXL),
                                    border: Border.all(
                                      color: isSelected ? AppUIv1.accent : AppUIv1.border,
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                    color: AppUIv1.surface,
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.all(AppUIv1.space4),
                                    leading: CircleAvatar(
                                      backgroundColor: isSelected ? AppUIv1.accentSoft : AppUIv1.surfaceMuted,
                                      child: Icon(
                                        Icons.bolt,
                                        color: isSelected ? AppUIv1.accentStrong : AppUIv1.inkSoft,
                                      ),
                                    ),
                                    title: Text('Auto-select (recommended)',
                                        style: Theme.of(context).textTheme.titleMedium),
                                    subtitle: Text(
                                      isSelected
                                          ? 'Selected \u2022 SecureWave picks the fastest server'
                                          : 'SecureWave picks the fastest server',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    trailing: isSelected
                                        ? const Icon(Icons.check_circle, color: AppUIv1.accent)
                                        : const Icon(Icons.chevron_right),
                                    onTap: () => ref.read(vpnStateProvider.notifier).selectServer(null),
                                  ),
                                ),
                              );
                            }

                            final server = sorted[index - 1];
                            final isSelected =
                                server.id == vpnState.selectedServerId;
                            final isFavorite = favorites.contains(server.id);
                            final latencyLabel = server.latencyMs == null
                                ? '-- ms'
                                : '${server.latencyMs} ms';
                            final subtitleParts = <String>[];
                            if (server.country != null &&
                                server.country!.isNotEmpty) {
                              subtitleParts.add(server.country!);
                            }
                            subtitleParts.add('Latency $latencyLabel');
                            final subtitle = subtitleParts.join(' \u2022 ');
                            return Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppUIv1.space3),
                              child: AnimatedContainer(
                                duration: AppUIv1.durationFast,
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(AppUIv1.radiusXL),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppUIv1.accent
                                        : AppUIv1.border,
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                  color: AppUIv1.surface,
                                ),
                                child: ListTile(
                                  contentPadding:
                                      const EdgeInsets.all(AppUIv1.space4),
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected
                                        ? AppUIv1.accentSoft
                                        : AppUIv1.surfaceMuted,
                                    child: Icon(
                                      Icons.public,
                                      color: isSelected
                                          ? AppUIv1.accentStrong
                                          : AppUIv1.inkSoft,
                                    ),
                                  ),
                                  title: Text(server.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  subtitle: Text(
                                    isSelected
                                        ? 'Selected \u2022 $subtitle'
                                        : subtitle,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: isFavorite
                                            ? 'Remove favorite'
                                            : 'Mark favorite',
                                        icon: AnimatedSwitcher(
                                          duration: AppUIv1.durationFast,
                                          child: Icon(
                                            isFavorite
                                                ? Icons.star
                                                : Icons.star_border,
                                            key: ValueKey(isFavorite),
                                          ),
                                        ),
                                        color: isFavorite
                                            ? AppUIv1.accentSun
                                            : AppUIv1.inkSoft,
                                        onPressed: () => ref
                                            .read(
                                                favoriteServersProvider.notifier)
                                            .toggle(server.id),
                                      ),
                                      if (isSelected)
                                        const Icon(Icons.check_circle,
                                            color: AppUIv1.accent)
                                      else
                                        const Icon(Icons.chevron_right),
                                    ],
                                  ),
                                  onTap: () => ref
                                      .read(vpnStateProvider.notifier)
                                      .selectServer(server.id),
                                ),
                              ),
                            );
                          },
                          childCount: sorted.length + 1,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppUIv1.space5)),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) =>
                const Center(child: Text('Unable to load regions. Please try again.')),
          ),
        ),
      ),
    );
  }
}

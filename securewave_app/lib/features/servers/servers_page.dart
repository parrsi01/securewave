import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/server_region.dart';
import '../../core/optimization/marlxgb.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_ui_v1.dart';
import '../../ui/securewave_ui.dart';

class ServersPage extends ConsumerWidget {
  const ServersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final vpnState = ref.watch(vpnStateProvider);
    final favorites = ref.watch(favoriteServersProvider);
    const predictor = MarLXGBPredictor();

    return SwPage(
      center: false,
      child: servers.when(
        data: (data) {
          final sorted = List.of(data);
          sorted.sort((a, b) {
            final aScore = predictor.scoreServer(
              a,
              isFavorite: favorites.contains(a.id),
            );
            final bScore = predictor.scoreServer(
              b,
              isFavorite: favorites.contains(b.id),
            );
            return bScore.compareTo(aScore);
          });

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SwSectionHeader(
                  eyebrow: 'Locations',
                  title: 'Route selection',
                  subtitle:
                      'Choose a tunnel region. Smart location keeps latency and preference signals balanced.',
                  trailing: SwStatusPill(
                    label: '${sorted.length} regions',
                    color: AppUIv1.accentCyan,
                    icon: Icons.public_rounded,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppUIv1.space5)),
              SliverToBoxAdapter(
                child: _AutoSelectCard(
                  selected: vpnState.selectedServerId == null,
                  onTap: () =>
                      ref.read(vpnStateProvider.notifier).selectServer(null),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppUIv1.space3)),
              if (sorted.isEmpty)
                const SliverToBoxAdapter(
                  child: SwPanel(
                    child: Text('No regions are available right now.'),
                  ),
                )
              else
                SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;
                    final columns = width >= 1050
                        ? 3
                        : width >= 680
                        ? 2
                        : 1;
                    return SliverGrid.builder(
                      itemCount: sorted.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: AppUIv1.space3,
                        mainAxisSpacing: AppUIv1.space3,
                        mainAxisExtent: 142,
                      ),
                      itemBuilder: (context, index) {
                        final server = sorted[index];
                        final isSelected =
                            server.id == vpnState.selectedServerId;
                        final isFavorite = favorites.contains(server.id);
                        return _ServerCard(
                          server: server,
                          selected: isSelected,
                          favorite: isFavorite,
                          score: predictor.scoreServer(
                            server,
                            isFavorite: isFavorite,
                          ),
                          onFavorite: () => ref
                              .read(favoriteServersProvider.notifier)
                              .toggle(server.id),
                          onTap: () => ref
                              .read(vpnStateProvider.notifier)
                              .selectServer(server.id),
                        );
                      },
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: AppUIv1.space6)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text('Unable to load regions. Please try again.'),
        ),
      ),
    );
  }
}

class _AutoSelectCard extends StatelessWidget {
  const _AutoSelectCard({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SwPanel(
      selected: selected,
      accent: AppUIv1.accentTeal,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: AppUIv1.brandGradient,
              borderRadius: BorderRadius.circular(AppUIv1.radiusM),
            ),
            child: const Icon(Icons.bolt_rounded, color: Colors.white),
          ),
          const SizedBox(width: AppUIv1.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart location',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppUIv1.space1),
                Text(
                  selected
                      ? 'Selected. SecureWave will pick the best route at connect time.'
                      : 'Let SecureWave choose the best region when you connect.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Icon(
            selected ? Icons.check_circle : Icons.chevron_right,
            color: selected ? AppUIv1.accentTeal : AppUIv1.inkSoft,
          ),
        ],
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.server,
    required this.selected,
    required this.favorite,
    required this.score,
    required this.onFavorite,
    required this.onTap,
  });

  final ServerRegion server;
  final bool selected;
  final bool favorite;
  final double score;
  final VoidCallback onFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final latency = server.latencyMs == null ? '--' : '${server.latencyMs}';
    final scorePercent = (score * 100).clamp(0, 100).toStringAsFixed(0);
    return SwPanel(
      selected: selected,
      accent: selected ? AppUIv1.accentCyan : AppUIv1.borderStrong,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppUIv1.accentCyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppUIv1.radiusM),
                  border: Border.all(
                    color: AppUIv1.accentCyan.withValues(alpha: 0.26),
                  ),
                ),
                child: const Icon(
                  Icons.public_rounded,
                  color: AppUIv1.accentCyan,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppUIv1.space3),
              Expanded(
                child: Text(
                  server.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: favorite ? 'Remove favorite' : 'Mark favorite',
                onPressed: onFavorite,
                icon: AnimatedSwitcher(
                  duration: AppUIv1.durationFast,
                  child: Icon(
                    favorite ? Icons.star_rounded : Icons.star_border_rounded,
                    key: ValueKey(favorite),
                    color: favorite ? AppUIv1.accentSun : AppUIv1.inkSoft,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            server.country ?? 'Global route',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppUIv1.space3),
          Row(
            children: [
              SwStatusPill(
                label: '$latency ms',
                color: AppUIv1.accentTeal,
                icon: Icons.speed_rounded,
              ),
              const Spacer(),
              Text(
                '$scorePercent score',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: AppUIv1.space2),
              Icon(
                selected ? Icons.check_circle : Icons.chevron_right,
                color: selected ? AppUIv1.accentCyan : AppUIv1.inkSoft,
                size: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

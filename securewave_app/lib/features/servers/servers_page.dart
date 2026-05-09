import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/server_region.dart';
import '../../core/optimization/marlxgb.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_ui_v1.dart';

class ServersPage extends ConsumerWidget {
  const ServersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final vpnState = ref.watch(vpnStateProvider);
    final favorites = ref.watch(favoriteServersProvider);
    const predictor = MarLXGBPredictor();

    return SecurePageBackground(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isWide = width >= AppUIv1.tabletBreakpoint;
            final padding = AppUIv1.pagePaddingFor(width);
            final availableWidth = width - padding.horizontal;
            final sidePadding = availableWidth > AppUIv1.shellMaxWidth
                ? (width - AppUIv1.shellMaxWidth) / 2
                : padding.left;
            final contentPadding = EdgeInsets.fromLTRB(
              sidePadding,
              padding.top,
              sidePadding,
              padding.bottom,
            );

            return servers.when(
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

                final options = [
                  const _ServerOption.auto(),
                  ...sorted.map(_ServerOption.region),
                ];

                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: contentPadding.copyWith(bottom: AppUIv1.space4),
                      sliver: SliverToBoxAdapter(
                        child: _ServersHeader(
                          selectedServerId: vpnState.selectedServerId,
                          serverCount: sorted.length,
                        ),
                      ),
                    ),
                    if (sorted.isEmpty)
                      SliverPadding(
                        padding: contentPadding.copyWith(top: 0),
                        sliver: const SliverToBoxAdapter(
                          child: _EmptyServersState(),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: contentPadding.copyWith(top: 0),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: isWide ? 2 : 1,
                            mainAxisExtent: isWide ? 156 : 148,
                            mainAxisSpacing: AppUIv1.space3,
                            crossAxisSpacing: AppUIv1.space3,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final option = options[index];
                              final isSelected = option.isAuto
                                  ? vpnState.selectedServerId == null
                                  : option.region!.id ==
                                      vpnState.selectedServerId;
                              final isFavorite = option.region != null &&
                                  favorites.contains(option.region!.id);
                              final score = option.region == null
                                  ? null
                                  : predictor.scoreServer(
                                      option.region!,
                                      isFavorite: isFavorite,
                                    );

                              return _ServerOptionCard(
                                option: option,
                                selected: isSelected,
                                favorite: isFavorite,
                                score: score,
                                onTap: () => ref
                                    .read(vpnStateProvider.notifier)
                                    .selectServer(option.region?.id),
                                onFavoriteToggle: option.region == null
                                    ? null
                                    : () => ref
                                        .read(favoriteServersProvider.notifier)
                                        .toggle(option.region!.id),
                              );
                            },
                            childCount: options.length,
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: AppUIv1.space5),
                    ),
                  ],
                );
              },
              loading: () => const _ServersLoadingState(),
              error: (_, __) => const _ServersErrorState(),
            );
          },
        ),
      ),
    );
  }
}

class _ServersHeader extends StatelessWidget {
  const _ServersHeader({
    required this.selectedServerId,
    required this.serverCount,
  });

  final String? selectedServerId;
  final int serverCount;

  @override
  Widget build(BuildContext context) {
    final regionCopy = serverCount == 1
        ? '1 available region'
        : '$serverCount available regions';

    return SecureSurface(
      variant: SecureSurfaceVariant.glass,
      padding: const EdgeInsets.all(AppUIv1.space5),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppUIv1.brandGradient,
              boxShadow: AppUIv1.glowAccent,
            ),
            child: const Icon(
              Icons.public_rounded,
              color: AppUIv1.background,
              size: 27,
            ),
          ),
          const SizedBox(width: AppUIv1.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Server selection',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: AppUIv1.space1),
                Text(
                  'Choose from $regionCopy. Auto-select keeps SecureWave in control.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppUIv1.space3),
          SecureStatePill(
            label: selectedServerId == null ? 'Auto' : 'Manual',
            color:
                selectedServerId == null ? AppUIv1.accentCyan : AppUIv1.accent,
            icon: selectedServerId == null
                ? Icons.auto_awesome_rounded
                : Icons.tune_rounded,
          ),
        ],
      ),
    );
  }
}

class _ServerOptionCard extends StatelessWidget {
  const _ServerOptionCard({
    required this.option,
    required this.selected,
    required this.favorite,
    required this.score,
    required this.onTap,
    required this.onFavoriteToggle,
  });

  final _ServerOption option;
  final bool selected;
  final bool favorite;
  final double? score;
  final VoidCallback onTap;
  final VoidCallback? onFavoriteToggle;

  @override
  Widget build(BuildContext context) {
    final region = option.region;
    final latency =
        region?.latencyMs == null ? '-- ms' : '${region!.latencyMs} ms';
    final locationParts = <String>[];
    if (region?.city != null && region!.city!.isNotEmpty) {
      locationParts.add(region.city!);
    }
    if (region?.country != null && region!.country!.isNotEmpty) {
      locationParts.add(region.country!);
    }
    final detail = option.isAuto
        ? 'Fastest region at connect time'
        : locationParts.isEmpty
            ? 'Region endpoint'
            : locationParts.join(' • ');
    final scoreLabel =
        score == null ? 'Adaptive' : '${(score! * 100).round()}% fit';

    return AnimatedContainer(
      duration: AppUIv1.durationNormal,
      curve: AppUIv1.curveDefault,
      decoration: BoxDecoration(
        color: selected
            ? AppUIv1.accentSoft
            : AppUIv1.surfaceRaised.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(AppUIv1.radiusCard),
        border: Border.all(
          color: selected ? AppUIv1.accent : AppUIv1.border,
          width: selected ? AppUIv1.strokeStrong : AppUIv1.hairline,
        ),
        boxShadow: selected ? AppUIv1.glowAccent : AppUIv1.shadowSm,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppUIv1.radiusCard),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppUIv1.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (option.isAuto
                                ? AppUIv1.accentCyan
                                : AppUIv1.accentBlue)
                            .withValues(alpha: selected ? 0.22 : 0.12),
                        border: Border.all(
                          color:
                              selected ? AppUIv1.accent : AppUIv1.borderStrong,
                        ),
                      ),
                      child: Icon(
                        option.isAuto
                            ? Icons.auto_awesome_rounded
                            : Icons.public_rounded,
                        color: selected ? AppUIv1.accent : AppUIv1.inkMuted,
                      ),
                    ),
                    const SizedBox(width: AppUIv1.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            option.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppUIv1.space1),
                          Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (onFavoriteToggle != null)
                      IconButton(
                        tooltip: favorite ? 'Remove favorite' : 'Mark favorite',
                        icon: AnimatedSwitcher(
                          duration: AppUIv1.durationFast,
                          child: Icon(
                            favorite ? Icons.star : Icons.star_border_rounded,
                            key: ValueKey(favorite),
                          ),
                        ),
                        color: favorite ? AppUIv1.accentSun : AppUIv1.inkSoft,
                        onPressed: onFavoriteToggle,
                      )
                    else
                      const Icon(
                        Icons.bolt_rounded,
                        color: AppUIv1.accentCyan,
                      ),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    SecureStatePill(
                      label: option.isAuto ? scoreLabel : latency,
                      color:
                          option.isAuto ? AppUIv1.accentCyan : AppUIv1.inkSoft,
                    ),
                    const SizedBox(width: AppUIv1.space2),
                    SecureStatePill(
                      label: selected ? 'Selected' : scoreLabel,
                      color: selected ? AppUIv1.accent : AppUIv1.inkSoft,
                      icon: selected ? Icons.check_rounded : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServersLoadingState extends StatelessWidget {
  const _ServersLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SecureSurface(
        variant: SecureSurfaceVariant.glass,
        padding: EdgeInsets.all(AppUIv1.space5),
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

class _ServersErrorState extends StatelessWidget {
  const _ServersErrorState();

  @override
  Widget build(BuildContext context) {
    return SecurePageBackground(
      child: Center(
        child: SecureSurface(
          variant: SecureSurfaceVariant.danger,
          padding: const EdgeInsets.all(AppUIv1.space5),
          child: Text(
            'Unable to load regions. Please try again.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}

class _EmptyServersState extends StatelessWidget {
  const _EmptyServersState();

  @override
  Widget build(BuildContext context) {
    return SecureSurface(
      variant: SecureSurfaceVariant.base,
      padding: const EdgeInsets.all(AppUIv1.space5),
      child: Column(
        children: [
          const Icon(
            Icons.public_off_rounded,
            color: AppUIv1.inkSoft,
            size: 34,
          ),
          const SizedBox(height: AppUIv1.space3),
          Text(
            'No regions are available right now.',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppUIv1.space1),
          Text(
            'SecureWave will keep using auto-select when the catalog returns.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ServerOption {
  const _ServerOption.auto() : region = null;

  const _ServerOption.region(this.region);

  final ServerRegion? region;

  bool get isAuto => region == null;

  String get label => isAuto ? 'Auto-select' : region!.name;
}

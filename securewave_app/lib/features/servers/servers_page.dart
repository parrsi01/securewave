import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/server_region.dart';
import '../../core/optimization/marlxgb.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';

class ServersPage extends ConsumerWidget {
  const ServersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final vpnState = ref.watch(vpnStateProvider);
    final favorites = ref.watch(favoriteServersProvider);
    const predictor = MarLXGBPredictor();
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: servers.when(
        data: (data) {
          final sorted = [...data];
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

          if (sorted.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No servers available.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final server = sorted[index];
              return _ServerTile(
                server: server,
                isSelected: server.id == vpnState.selectedServerId,
                isFavorite: favorites.contains(server.id),
                onTap: () => ref
                    .read(vpnStateProvider.notifier)
                    .selectServer(server.id),
                onToggleFavorite: () => ref
                    .read(favoriteServersProvider.notifier)
                    .toggle(server.id),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Unable to load servers: $error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.server,
    required this.isSelected,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final ServerRegion server;
  final bool isSelected;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = [
      if (server.country?.isNotEmpty ?? false) server.country!,
      if (server.latencyMs != null) '${server.latencyMs} ms',
    ].join('  ·  ');

    return Card(
      shape: isSelected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: cs.primary.withValues(alpha: 0.5)),
            )
          : null,
      child: ListTile(
        selected: isSelected,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor:
              isSelected ? cs.primaryContainer : cs.surfaceContainerHigh,
          child: Icon(
            Icons.public_rounded,
            size: 20,
            color: isSelected ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
        title: Text(server.name),
        subtitle: subtitle.isNotEmpty
            ? Text(subtitle)
            : const Text('Region available'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                size: 20,
              ),
              color: isFavorite ? cs.primary : cs.onSurfaceVariant,
              onPressed: onToggleFavorite,
              visualDensity: VisualDensity.compact,
            ),
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.chevron_right_rounded,
              size: 20,
              color: isSelected ? cs.primary : cs.onSurfaceVariant,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

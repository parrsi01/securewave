import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/optimization/marlxgb.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_ui_v1.dart';
import '../../ui/server_card.dart';

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
          final sorted = [...data];
          sorted.sort((a, b) {
            final aScore =
                predictor.scoreServer(a, isFavorite: favorites.contains(a.id));
            final bScore =
                predictor.scoreServer(b, isFavorite: favorites.contains(b.id));
            return bScore.compareTo(aScore);
          });

          return ListView(
            padding: const EdgeInsets.all(AppUIv1.space5),
            children: [
              Text('Server selection',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppUIv1.space2),
              Text(
                'Choose the fastest region for your next connection.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppUIv1.space4),
              for (final server in sorted) ...[
                ServerCard(
                  server: server,
                  isSelected: server.id == vpnState.selectedServerId,
                  isFavorite: favorites.contains(server.id),
                  onTap: () => ref
                      .read(vpnStateProvider.notifier)
                      .selectServer(server.id),
                  onToggleFavorite: () => ref
                      .read(favoriteServersProvider.notifier)
                      .toggle(server.id),
                ),
                const SizedBox(height: AppUIv1.space3),
              ],
              if (sorted.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppUIv1.space4),
                    child: Text(
                      'No servers available from the backend.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppUIv1.space5),
            child: Text('Unable to load servers: $error'),
          ),
        ),
      ),
    );
  }
}

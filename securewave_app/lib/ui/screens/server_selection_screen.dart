import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/widgets/ui_helpers.dart';
import '../components/server_card.dart';

/// Server / location selection screen.
class ServerSelectionScreen extends ConsumerWidget {
  const ServerSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serversAsync = ref.watch(serversProvider);
    final vpnState = ref.watch(vpnStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servers'),
        centerTitle: false,
      ),
      body: serversAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Failed to load servers: $e'),
        ),
        data: (servers) {
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            itemCount: servers.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppSpacing.itemGap),
            itemBuilder: (context, index) {
              final server = servers[index];
              final isSelected = vpnState.selectedServerId == server.id;
              return ServerCard(
                server: server,
                isSelected: isSelected,
                onTap: () {
                  ref
                      .read(vpnStateProvider.notifier)
                      .selectServer(server.id);
                },
                trailing: Text(
                  latencyLabel(server.latencyMs),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.inkSoft,
                      ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

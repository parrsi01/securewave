import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/app_state.dart';
import '../../ui/app_ui_v1.dart';
import '../vpn/vpn_controller.dart';

class ServersPage extends ConsumerWidget {
  const ServersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final vpnState = ref.watch(vpnControllerProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppUIv1.space5),
        children: [
          Text('Choose a region', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppUIv1.space2),
          Text(
            'SecureWave will use this region whenever you connect.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppUIv1.space4),
          servers.when(
            data: (data) {
              if (data.isEmpty) {
                return const Text('No regions are available right now.');
              }
              if (vpnState.selectedServerId == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  ref.read(vpnControllerProvider.notifier).selectServer(
                        data.first['server_id'] as String?,
                      );
                });
              }
              return Column(
                children: data.map((server) {
                  final id = server['server_id'] as String?;
                  final location = server['location']?.toString() ?? 'Unknown region';
                  final isSelected = id != null && id == vpnState.selectedServerId;
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
                          backgroundColor: isSelected ? AppUIv1.accentSoft : AppUIv1.surfaceMuted,
                          child: Icon(Icons.public, color: isSelected ? AppUIv1.accentStrong : AppUIv1.inkSoft),
                        ),
                        title: Text(location, style: Theme.of(context).textTheme.titleMedium),
                        subtitle: Text(
                          isSelected ? 'Selected for next connection' : 'Tap to select',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: AppUIv1.accent)
                            : const Icon(Icons.chevron_right),
                        onTap: () => ref.read(vpnControllerProvider.notifier).selectServer(id),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Text('Unable to load regions. Please try again.'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/buttons/primary_button.dart';
import '../../widgets/layouts/section_header.dart';
import '../../widgets/loaders/app_loader.dart';
import '../../widgets/loaders/inline_banner.dart';
import 'devices_controller.dart';

class DevicesPage extends ConsumerStatefulWidget {
  const DevicesPage({super.key});

  @override
  ConsumerState<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends ConsumerState<DevicesPage> {
  final _deviceController = TextEditingController();

  @override
  void dispose() {
    _deviceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(devicesControllerProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Manage devices',
              subtitle: 'Provision and revoke access for each device.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _deviceController,
              decoration: const InputDecoration(labelText: 'Device name (e.g., MacBook Pro)'),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Add device',
              isLoading: state.isLoading,
              onPressed: () {
                final name = _deviceController.text.trim();
                if (name.isEmpty) return;
                ref.read(devicesControllerProvider.notifier).addDevice(name);
                _deviceController.clear();
              },
            ),
            if (state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: InlineBanner(message: state.errorMessage!),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: state.isLoading && state.devices.isEmpty
                  ? const AppLoader()
                  : ListView.separated(
                      itemCount: state.devices.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final device = state.devices[index];
                        final name = device['device_name'] ?? 'Unnamed device';
                        final id = device['id']?.toString() ?? '';
                        final type = device['device_type'] ?? 'Device';
                        return Card(
                          child: ListTile(
                            title: Text(name),
                            subtitle: Text(type.toString().toUpperCase()),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'revoke') {
                                  ref.read(devicesControllerProvider.notifier).revokeDevice(id);
                                } else if (value == 'rotate') {
                                  ref.read(devicesControllerProvider.notifier).rotateKeys(id);
                                } else if (value == 'rename') {
                                  _renameDevice(context, id, name.toString());
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(value: 'rename', child: Text('Rename device')),
                                const PopupMenuItem(value: 'rotate', child: Text('Rotate keys')),
                                const PopupMenuItem(value: 'revoke', child: Text('Revoke device')),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameDevice(BuildContext context, String id, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename device'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Device name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      await ref.read(devicesControllerProvider.notifier).renameDevice(id, newName);
    }
  }
}

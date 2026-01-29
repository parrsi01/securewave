import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bootstrap/boot_controller.dart';
import '../../core/logging/app_logger.dart';
import '../../ui/app_ui_v1.dart';

class BootScreen extends ConsumerWidget {
  const BootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(bootControllerProvider).state;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppUIv1.space5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SecureWave', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: AppUIv1.space2),
              Text(
                boot.status == BootStatus.failed
                    ? 'Startup needs attention.'
                    : 'Preparing your secure connection...',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppUIv1.space4),
              if (boot.status == BootStatus.initializing)
                const LinearProgressIndicator(minHeight: 3),
              if (boot.status == BootStatus.failed && boot.errorMessage != null) ...[
                const SizedBox(height: AppUIv1.space3),
                Text(
                  boot.errorMessage!,
                  style: const TextStyle(color: AppUIv1.warning),
                ),
              ],
              const SizedBox(height: AppUIv1.space4),
              Expanded(
                child: ValueListenableBuilder<List<AppLogEntry>>(
                  valueListenable: AppLogger.logStream,
                  builder: (context, logs, _) {
                    return Container(
                      padding: const EdgeInsets.all(AppUIv1.space3),
                      decoration: BoxDecoration(
                        color: AppUIv1.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppUIv1.border),
                      ),
                      child: ListView.builder(
                        itemCount: logs.length,
                        itemBuilder: (context, index) {
                          final entry = logs[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              entry.toString(),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

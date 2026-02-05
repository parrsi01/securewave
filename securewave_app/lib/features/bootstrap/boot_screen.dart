import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/bootstrap/boot_controller.dart';
import '../../core/logging/app_logger.dart';
import '../../ui/app_ui_v1.dart';

class BootScreen extends ConsumerWidget {
  const BootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(bootControllerProvider).state;
    final isFailed = boot.status == BootStatus.failed;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppUIv1.authMaxWidth),
            child: Padding(
              padding: const EdgeInsets.all(AppUIv1.space5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),
                  // Logo
                  SvgPicture.asset(
                    'assets/securewave_logo.svg',
                    width: 64,
                    height: 64,
                  ),
                  const SizedBox(height: AppUIv1.space4),
                  Text(
                    'SecureWave',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppUIv1.space2),
                  AnimatedSwitcher(
                    duration: AppUIv1.durationNormal,
                    child: Text(
                      isFailed
                          ? 'Startup needs attention.'
                          : 'Preparing your secure connection...',
                      key: ValueKey(isFailed),
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: AppUIv1.space5),
                  if (!isFailed)
                    SizedBox(
                      width: 200,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppUIv1.radiusFull),
                        child: const LinearProgressIndicator(minHeight: 3),
                      ),
                    ),
                  if (isFailed && boot.errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(AppUIv1.space3),
                      decoration: BoxDecoration(
                        color: AppUIv1.warning.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppUIv1.radiusM),
                      ),
                      child: Text(
                        boot.errorMessage!,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppUIv1.warning),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const Spacer(flex: 2),
                  // Boot log (collapsed, expandable)
                  Expanded(
                    flex: 3,
                    child: ValueListenableBuilder<List<AppLogEntry>>(
                      valueListenable: AppLogger.logStream,
                      builder: (context, logs, _) {
                        return AnimatedOpacity(
                          duration: AppUIv1.durationNormal,
                          opacity: logs.isEmpty ? 0 : 0.6,
                          child: Container(
                            padding: const EdgeInsets.all(AppUIv1.space3),
                            decoration: BoxDecoration(
                              color: AppUIv1.surface,
                              borderRadius: BorderRadius.circular(AppUIv1.radiusL),
                              border: Border.all(color: AppUIv1.border),
                            ),
                            child: ListView.builder(
                              itemCount: logs.length,
                              reverse: true,
                              itemBuilder: (context, index) {
                                final entry = logs[logs.length - 1 - index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    entry.toString(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(fontSize: 11),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

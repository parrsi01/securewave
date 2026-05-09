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
      body: SecurePageBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final padding = AppUIv1.pagePaddingFor(constraints.maxWidth);
              return SingleChildScrollView(
                padding: padding,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - padding.vertical)
                        .clamp(0.0, double.infinity)
                        .toDouble(),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppUIv1.authMaxWidth,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SecureSurface(
                            variant: isFailed
                                ? SecureSurfaceVariant.warning
                                : SecureSurfaceVariant.glass,
                            radius: AppUIv1.radiusXXL,
                            padding: const EdgeInsets.all(AppUIv1.space6),
                            child: Column(
                              children: [
                                Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: AppUIv1.brandGradient,
                                    boxShadow: isFailed
                                        ? AppUIv1.shadowMd
                                        : AppUIv1.glowAccent,
                                  ),
                                  child: Center(
                                    child: SvgPicture.asset(
                                      'assets/securewave_logo.svg',
                                      width: 48,
                                      height: 48,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppUIv1.space4),
                                Text(
                                  'SecureWave',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: AppUIv1.space2),
                                AnimatedSwitcher(
                                  duration: AppUIv1.durationNormal,
                                  switchInCurve: AppUIv1.curveEnter,
                                  switchOutCurve: AppUIv1.curveExit,
                                  child: Text(
                                    isFailed
                                        ? 'Startup needs attention.'
                                        : 'Preparing your secure connection...',
                                    key: ValueKey(isFailed),
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(height: AppUIv1.space5),
                                if (!isFailed)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      AppUIv1.radiusFull,
                                    ),
                                    child: const LinearProgressIndicator(
                                      minHeight: 3,
                                    ),
                                  )
                                else if (boot.errorMessage != null)
                                  SecureSurface(
                                    variant: SecureSurfaceVariant.warning,
                                    padding: const EdgeInsets.all(
                                      AppUIv1.space3,
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
                            ),
                          ),
                          const SizedBox(height: AppUIv1.space4),
                          ValueListenableBuilder<List<AppLogEntry>>(
                            valueListenable: AppLogger.logStream,
                            builder: (context, logs, _) {
                              return AnimatedSwitcher(
                                duration: AppUIv1.durationNormal,
                                child: logs.isEmpty
                                    ? const SizedBox.shrink()
                                    : SecureSurface(
                                        key: ValueKey(logs.length),
                                        variant: SecureSurfaceVariant.base,
                                        padding: const EdgeInsets.all(
                                          AppUIv1.space3,
                                        ),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxHeight: 148,
                                          ),
                                          child: ListView.builder(
                                            itemCount: logs.length,
                                            reverse: true,
                                            shrinkWrap: true,
                                            itemBuilder: (context, index) {
                                              final entry =
                                                  logs[logs.length - 1 - index];
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: AppUIv1.space1,
                                                ),
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
                                      ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

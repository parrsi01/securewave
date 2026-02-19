import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/bootstrap/boot_controller.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/design/app_animations.dart';

class BootScreen extends ConsumerStatefulWidget {
  const BootScreen({super.key});

  @override
  ConsumerState<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends ConsumerState<BootScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boot = ref.watch(bootControllerProvider).state;
    final isFailed = boot.status == BootStatus.failed;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.authMaxWidth),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 3),
                  // Pulsing logo
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Hero(
                      tag: 'securewave_logo',
                      child: SvgPicture.asset(
                        'assets/securewave_logo.svg',
                        width: 72,
                        height: 72,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space4),
                  Text(
                    'SecureWave',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  AnimatedSwitcher(
                    duration: AppAnimations.durationNormal,
                    child: Text(
                      isFailed
                          ? 'Startup needs attention.'
                          : 'Preparing your secure connection\u2026',
                      key: ValueKey(isFailed),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.inkMuted,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space5),
                  if (!isFailed)
                    SizedBox(
                      width: 200,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                        child: const LinearProgressIndicator(minHeight: 3),
                      ),
                    ),
                  if (isFailed) ...[
                    if (boot.errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.space3),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                        ),
                        child: Text(
                          boot.errorMessage!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.error),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space4),
                    ],
                    FilledButton.icon(
                      onPressed: () => ref.invalidate(bootControllerProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                  const Spacer(flex: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

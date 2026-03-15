import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/bootstrap/boot_controller.dart';
import '../../ui/design/app_animations.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';

/// Boot screen — v2.
///
/// Brand-immersive dark teal background with concentric animated rings
/// emanating outward from the logo. Creates a "secure tunnel" visual effect.
class BootScreen extends ConsumerStatefulWidget {
  const BootScreen({super.key});

  @override
  ConsumerState<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends ConsumerState<BootScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _ringCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _scaleAnim = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boot = ref.watch(bootControllerProvider).state;
    final isFailed = boot.status == BootStatus.failed;
    final stepLabel = boot.stepLabel?.trim().isNotEmpty == true
        ? boot.stepLabel!.trim()
        : null;
    final stepDetail = boot.stepDetail?.trim().isNotEmpty == true
        ? boot.stepDetail!.trim()
        : null;
    final headlineText = isFailed
        ? 'Startup needs attention.'
        : (stepLabel ?? 'Preparing your secure connection…');

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Stack(
        children: [
          // ── Concentric ring background ─────────────────────────────
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _ringCtrl,
                builder: (context, _) => CustomPaint(
                  painter: _ConcentricRingsPainter(
                    progress: _ringCtrl.value,
                    color: AppColors.primaryBright,
                  ),
                ),
              ),
            ),
          ),

          // ── Content ────────────────────────────────────────────────
          SafeArea(
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
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth.isFinite
                              ? constraints.maxWidth
                              : MediaQuery.sizeOf(context).width;
                          final shellSize =
                              (width * 0.26).clamp(80.0, 104.0).toDouble();
                          final logoSize = shellSize * 0.54;

                          return ScaleTransition(
                            scale: _scaleAnim,
                            child: Hero(
                              tag: 'securewave_logo',
                              child: Container(
                                width: shellSize,
                                height: shellSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.darkSurface
                                      .withValues(alpha: 0.8),
                                  border: Border.all(
                                    color: AppColors.primaryBright
                                        .withValues(alpha: 0.3),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primaryBright
                                          .withValues(alpha: 0.20),
                                      blurRadius: 32,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: SvgPicture.asset(
                                    'assets/securewave_logo.svg',
                                    width: logoSize,
                                    height: logoSize,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: AppSpacing.space5),

                      const Text(
                        'SecureWave',
                        style: TextStyle(
                          color: AppColors.darkInk,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space2),

                      AnimatedSwitcher(
                        duration: AppAnimations.durationNormal,
                        child: Text(
                          headlineText,
                          key: ValueKey('${boot.status.name}:$headlineText'),
                          style: const TextStyle(
                            color: AppColors.darkInkMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                      if (!isFailed && stepDetail != null) ...[
                        const SizedBox(height: AppSpacing.space2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.space3,
                            vertical: AppSpacing.space2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.darkSurface.withValues(alpha: 0.55),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusL),
                            border: Border.all(
                              color: AppColors.primaryBright.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.manage_search_rounded,
                                size: 14,
                                color: AppColors.primaryBright.withValues(alpha: 0.9),
                              ),
                              const SizedBox(width: AppSpacing.space2),
                              Flexible(
                                child: Text(
                                  stepDetail,
                                  style: const TextStyle(
                                    color: AppColors.darkInkMuted,
                                    fontSize: 12,
                                    height: 1.25,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: AppSpacing.space6),

                      // Progress bar or error state
                      if (!isFailed)
                        SizedBox(
                          width: 160,
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusFull),
                            child: const LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: AppColors.darkBorder,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.primaryBright),
                            ),
                          ),
                        ),

                      if (isFailed) ...[
                        if (boot.errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.space3),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusL),
                              border: Border.all(
                                  color:
                                      AppColors.error.withValues(alpha: 0.25)),
                            ),
                            child: Text(
                              boot.errorMessage!,
                              style: const TextStyle(
                                color: Color(0xFFFF6B6B),
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.space4),
                        ],
                        FilledButton.icon(
                          onPressed: () => ref.invalidate(bootControllerProvider),
                          icon: const Icon(Icons.refresh_rounded, size: AppSpacing.iconXS),
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
        ],
      ),
    );
  }
}

// ── Concentric rings painter ───────────────────────────────────────────────

class _ConcentricRingsPainter extends CustomPainter {
  _ConcentricRingsPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.sqrt(
            size.width * size.width + size.height * size.height) /
        2;

    const ringCount = 4;
    for (int i = 0; i < ringCount; i++) {
      final t = ((progress + i / ringCount) % 1.0);
      final radius = t * maxRadius;
      final alpha = (1.0 - t) * 0.06;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_ConcentricRingsPainter old) =>
      progress != old.progress || color != old.color;
}

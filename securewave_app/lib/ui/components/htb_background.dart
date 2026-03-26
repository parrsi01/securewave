import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_spacing.dart';
import '../theme/app_colors.dart' as htb;

// ─────────────────────────────────────────────────────────────────────────────
// HtbBackground
// ─────────────────────────────────────────────────────────────────────────────

/// Lightweight animated SecureWave ambient background for use as the bottom
/// layer in a Stack.
class HtbBackground extends StatelessWidget {
  const HtbBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.86, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        final drift = 1 - value;
        return Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.darkBackground,
                    AppColors.darkBackgroundWarm,
                    AppColors.darkSurface,
                  ],
                  stops: [0.0, 0.52, 1.0],
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(-42 * drift, -56 * drift),
              child: const Opacity(
                opacity: 0.78,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-0.72, -0.96),
                      radius: 1.08,
                      colors: [
                        AppColors.ambientGlowPrimary,
                        AppColors.ambientGlowSecondary,
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.26, 0.82],
                    ),
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(48 * drift, 76 * drift),
              child: const Opacity(
                opacity: 0.54,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0.92, 1.08),
                      radius: 0.92,
                      colors: [
                        AppColors.ambientGlowSecondary,
                        AppColors.ambientGlowTertiary,
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.22, 0.74],
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: IgnorePointer(
                child: Container(
                  height: 220,
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space6,
                    vertical: AppSpacing.space4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXXL),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        htb.HtbColors.accentSecondaryGhost.withValues(
                          alpha: 0.16 * value,
                        ),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: _GridPainter()),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grid painter
// ─────────────────────────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  const _GridPainter();

  static const double _cellSize = 64;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.darkGridLine
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // Vertical lines
    double x = 0;
    while (x <= size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      x += _cellSize;
    }

    // Horizontal lines
    double y = 0;
    while (y <= size.height) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      y += _cellSize;
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// HtbScaffoldBackground
// ─────────────────────────────────────────────────────────────────────────────

/// Convenience wrapper: fills the scaffold area with the solid bg0 color
/// and overlays HtbBackground effects. Use this as the body's Stack base.
class HtbScaffoldBackground extends StatelessWidget {
  const HtbScaffoldBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ColoredBox(
            color: AppColors.darkBackground, child: SizedBox.expand()),
        const HtbBackground(),
        child,
      ],
    );
  }
}

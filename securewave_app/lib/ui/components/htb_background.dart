import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_spacing.dart';
import '../theme/app_colors.dart' as htb;

// ─────────────────────────────────────────────────────────────────────────────
// HtbBackground
// ─────────────────────────────────────────────────────────────────────────────

/// Lightweight animated SecureWave ambient background for use as the bottom
/// layer in a Stack. Dark plum base, neon purple/lavender ambient glow.
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
            // Near-black base gradient
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.background,
                    AppColors.backgroundWarm,
                    AppColors.surfaceMuted,
                  ],
                  stops: [0.0, 0.52, 1.0],
                ),
              ),
            ),
            // Neon purple radial glow top-left
            Transform.translate(
              offset: Offset(-42 * drift, -56 * drift),
              child: Opacity(
                opacity: 0.78 * value,
                child: const DecoratedBox(
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
            // Neon purple glow bottom-right
            Transform.translate(
              offset: Offset(48 * drift, 76 * drift),
              child: Opacity(
                opacity: 0.78 * value,
                child: const DecoratedBox(
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
            // Subtle top-center neon wash
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
                        htb.HtbColors.accentPrimaryGhost.withValues(
                          alpha: 0.06 * value,
                        ),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Faint purple grid
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
    // Faint purple at ~5% opacity — subtle on dark backgrounds
    final paint = Paint()
      ..color = const Color(0x0D7A5CFF)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    double x = 0;
    while (x <= size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      x += _cellSize;
    }

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

/// Convenience wrapper: fills the scaffold area with near-black and overlays
/// HtbBackground ambient effects.
class HtbScaffoldBackground extends StatelessWidget {
  const HtbScaffoldBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ColoredBox(
            color: AppColors.background, child: SizedBox.expand()),
        const HtbBackground(),
        child,
      ],
    );
  }
}

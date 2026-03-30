import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HtbBackground
// ─────────────────────────────────────────────────────────────────────────────

/// Purple gradient background — light plum at top fading to near-black.
/// Mirrors the green-era concept: soft radial bloom from upper-left corner
/// over a linear dark base. Fine grid overlay for depth.
class HtbBackground extends StatelessWidget {
  const HtbBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const Stack(
      fit: StackFit.expand,
      children: [
        // ── Base: top-left lighter purple → near-black bottom-right ──────────
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF130C24), // muted plum — lighter purple hue
                Color(0xFF0D0915), // mid transition
                AppColors.background, // #07090F near-black
              ],
              stops: [0.0, 0.42, 1.0],
            ),
          ),
        ),

        // ── Radial bloom: top-left purple glow (green-era concept) ───────────
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.6, -0.95),
              radius: 1.15,
              colors: [
                Color(0x287A5CFF), // primary ~16% — visible bloom
                Color(0x127A5CFF), // primary ~7%
                Color(0x057A5CFF), // primary ~2%
                Colors.transparent,
              ],
              stops: [0.0, 0.22, 0.48, 0.82],
            ),
          ),
        ),

        // ── Secondary: subtle bottom-right counter-glow ───────────────────────
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(1.0, 1.1),
              radius: 0.80,
              colors: [
                Color(0x107A5CFF), // primary ~6%
                Colors.transparent,
              ],
              stops: [0.0, 0.70],
            ),
          ),
        ),

        // ── Fine grid ─────────────────────────────────────────────────────────
        Positioned.fill(child: CustomPaint(painter: _GridPainter())),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  const _GridPainter();

  static const double _cellSize = 64;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x0F7A5CFF) // purple-tinted grid lines ~6%
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

/// Wraps any widget with the full gradient background layer.
class HtbScaffoldBackground extends StatelessWidget {
  const HtbScaffoldBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(color: HtbColors.bg0),
          ),
        ),
        const SizedBox.expand(child: HtbBackground()),
        child,
      ],
    );
  }
}

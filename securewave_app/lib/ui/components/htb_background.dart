import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HtbBackground
// ─────────────────────────────────────────────────────────────────────────────

/// Static SecureWave ambient background for use as the bottom layer in a Stack.
class HtbBackground extends StatelessWidget {
  const HtbBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Soft ambient glow.
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.6, -1.0),
              radius: 1.2,
              colors: [
                Color(0x1C4DDFC9),
                Color(0x0C7BB8FF),
                Colors.transparent,
              ],
              stops: [0.0, 0.22, 0.7],
            ),
          ),
        ),

        // Fine technical grid.
        const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
      ],
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
      ..color = const Color(0x0A8CBFD7)
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
        const ColoredBox(color: HtbColors.bg0, child: SizedBox.expand()),
        const HtbBackground(),
        child,
      ],
    );
  }
}

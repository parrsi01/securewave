import 'package:flutter/material.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).scaffoldBackgroundColor;
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                surface,
                surface.withOpacity(0.94),
                surface.withOpacity(0.9),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Positioned(
          top: -120,
          right: -80,
          child: _GlowBlob(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.25),
            size: 280,
          ),
        ),
        Positioned(
          bottom: -140,
          left: -90,
          child: _GlowBlob(
            color: Theme.of(context).colorScheme.secondary.withOpacity(0.2),
            size: 300,
          ),
        ),
        Positioned(
          bottom: 40,
          right: -60,
          child: _GlowBlob(
            color: Theme.of(context).colorScheme.tertiary.withOpacity(0.18),
            size: 220,
          ),
        ),
        child,
      ],
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
          ),
        ),
      ),
    );
  }
}

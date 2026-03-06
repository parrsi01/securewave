import 'package:flutter/material.dart';

class SecureWaveMotionArt extends StatefulWidget {
  const SecureWaveMotionArt({
    super.key,
    this.opacity = 0.35,
    this.padding = const EdgeInsets.all(12),
  });

  final double opacity;
  final EdgeInsetsGeometry padding;

  @override
  State<SecureWaveMotionArt> createState() => _SecureWaveMotionArtState();
}

class _SecureWaveMotionArtState extends State<SecureWaveMotionArt> {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: widget.opacity,
        child: Padding(
          padding: widget.padding,
          child: const _MotionField(),
        ),
      ),
    );
  }
}

class _MotionField extends StatefulWidget {
  const _MotionField();

  @override
  State<_MotionField> createState() => _MotionFieldState();
}

class _MotionFieldState extends State<_MotionField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                scheme.primary.withValues(alpha: 0.08 + (t * 0.03)),
                scheme.surface.withValues(alpha: 0.02),
                Colors.transparent.withValues(alpha: 0),
              ],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Align(
                alignment: Alignment(-0.68 + (t * 0.24), -0.48),
                child: _GlowOrb(
                  size: 96 + (t * 18),
                  color: scheme.primary.withValues(alpha: 0.16),
                ),
              ),
              Align(
                alignment: Alignment(0.52 - (t * 0.22), 0.18 + (t * 0.12)),
                child: _GlowOrb(
                  size: 78 + ((1 - t) * 14),
                  color: scheme.tertiary.withValues(alpha: 0.12),
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.outline.withValues(alpha: 0.12),
                    ),
                    gradient: RadialGradient(
                      colors: <Color>[
                        scheme.surface.withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color,
            blurRadius: size * 0.32,
            spreadRadius: size * 0.04,
          ),
        ],
      ),
    );
  }
}

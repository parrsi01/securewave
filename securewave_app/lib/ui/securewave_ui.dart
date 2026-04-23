import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_ui_v1.dart';

class SwPage extends StatelessWidget {
  const SwPage({
    super.key,
    required this.child,
    this.maxWidth = AppUIv1.contentMaxWidth,
    this.padding,
    this.center = true,
    this.safeArea = true,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final bool center;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(
        padding: padding ??
            const EdgeInsets.symmetric(
              horizontal: AppUIv1.space5,
              vertical: AppUIv1.space4,
            ),
        child: child,
      ),
    );

    final body = SwSecurityBackdrop(
      child: center ? Center(child: content) : content,
    );
    return safeArea ? SafeArea(child: body) : body;
  }
}

class SwSecurityBackdrop extends StatelessWidget {
  const SwSecurityBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppUIv1.background),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _SecurityGridPainter())),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppUIv1.background,
                      AppUIv1.backgroundStrong.withValues(alpha: 0.90),
                      AppUIv1.background,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _SecurityGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppUIv1.border.withValues(alpha: 0.14)
      ..strokeWidth = 0.7;
    const step = 48.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppUIv1.accentCyan.withValues(alpha: 0.09);
    for (var i = 0; i < 3; i++) {
      final path = Path();
      final yBase = size.height * (0.18 + i * 0.18);
      path.moveTo(-40, yBase);
      for (double x = -40; x <= size.width + 40; x += 36) {
        final y = yBase + math.sin((x / 90) + i) * 18;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, wavePaint);
    }

    final diagonalPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = AppUIv1.accentViolet.withValues(alpha: 0.07);
    for (double x = -size.height; x < size.width; x += 160) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        diagonalPaint,
      );
    }

    final scanPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          AppUIv1.accentStrong.withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, scanPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SwPanel extends StatefulWidget {
  const SwPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppUIv1.space4),
    this.accent,
    this.onTap,
    this.selected = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;
  final VoidCallback? onTap;
  final bool selected;

  @override
  State<SwPanel> createState() => _SwPanelState();
}

class _SwPanelState extends State<SwPanel> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? AppUIv1.borderStrong;
    final borderColor = widget.selected || _hovered ? accent : AppUIv1.border;
    final lift = widget.onTap == null
        ? 0.0
        : _pressed
            ? 1.0
            : _hovered
                ? -2.0
                : 0.0;
    final scale = widget.onTap == null
        ? 1.0
        : _pressed
            ? 0.994
            : _hovered
                ? 1.004
                : 1.0;
    final content = AnimatedScale(
      scale: scale,
      duration: AppUIv1.durationNormal,
      curve: AppUIv1.curveDefault,
      child: AnimatedContainer(
        duration: AppUIv1.durationNormal,
        curve: AppUIv1.curveDefault,
        transform: Matrix4.translationValues(0, lift, 0),
        padding: widget.padding,
        decoration: BoxDecoration(
          color: AppUIv1.surfaceGlass,
          borderRadius: BorderRadius.circular(AppUIv1.radiusL),
          border: Border.all(
            color: borderColor,
            width: widget.selected ? 1.3 : 1,
          ),
          gradient: LinearGradient(
            colors: [
              Colors.white.withValues(alpha: widget.selected ? 0.045 : 0.025),
              Colors.white.withValues(alpha: 0.006),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            ...AppUIv1.shadowSm,
            if (widget.selected || _hovered)
              BoxShadow(
                color: accent.withValues(alpha: 0.18),
                blurRadius: 30,
                spreadRadius: -11,
              ),
          ],
        ),
        child: widget.child,
      ),
    );

    if (widget.onTap == null) return content;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppUIv1.radiusL),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppUIv1.radiusL),
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          child: content,
        ),
      ),
    );
  }
}

class SwSectionHeader extends StatelessWidget {
  const SwSectionHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppUIv1.accentCyan,
                      fontSize: 11,
                    ),
              ),
              const SizedBox(height: AppUIv1.space1),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              if (subtitle != null) ...[
                const SizedBox(height: AppUIv1.space2),
                Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppUIv1.space4),
          trailing!,
        ],
      ],
    );
  }
}

class SwBrandLockup extends StatelessWidget {
  const SwBrandLockup({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          'assets/securewave_logo.svg',
          width: compact ? 28 : 38,
          height: compact ? 28 : 38,
        ),
        const SizedBox(width: AppUIv1.space2),
        Text(
          'SecureWave',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class SwStatusPill extends StatefulWidget {
  const SwStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.pulse = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool pulse;

  @override
  State<SwStatusPill> createState() => _SwStatusPillState();
}

class _SwStatusPillState extends State<SwStatusPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppUIv1.durationScan,
    );
    if (widget.pulse) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant SwStatusPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulse && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final glow = widget.pulse ? 0.10 + (_controller.value * 0.18) : 0.10;
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppUIv1.space3,
            vertical: AppUIv1.space2,
          ),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppUIv1.radiusFull),
            border: Border.all(color: widget.color.withValues(alpha: 0.48)),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: glow),
                blurRadius: 18,
                spreadRadius: -8,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 14, color: widget.color),
            const SizedBox(width: 6),
          ],
          Text(
            widget.label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: widget.color,
                  fontSize: 12,
                ),
          ),
        ],
      ),
    );
  }
}

class SwMetricTile extends StatelessWidget {
  const SwMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppUIv1.accentCyan,
    this.caption,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return SwPanel(
      padding: const EdgeInsets.all(AppUIv1.space3),
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: AppUIv1.space2),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppUIv1.space2),
          AnimatedSwitcher(
            duration: AppUIv1.durationNormal,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.18),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Text(
              value,
              key: ValueKey(value),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: AppUIv1.space1),
            Text(caption!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class SwActionTile extends StatelessWidget {
  const SwActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.color = AppUIv1.accentCyan,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SwPanel(
      onTap: onTap,
      selected: selected,
      accent: color,
      padding: const EdgeInsets.all(AppUIv1.space4),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppUIv1.radiusM),
              border: Border.all(color: color.withValues(alpha: 0.28)),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: AppUIv1.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppUIv1.space3),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class SwMiniGraph extends StatelessWidget {
  const SwMiniGraph({
    super.key,
    required this.color,
    this.values = const [0.2, 0.45, 0.30, 0.62, 0.48, 0.74, 0.58, 0.86],
  });

  final Color color;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: CustomPaint(
        painter: _MiniGraphPainter(color: color, values: values),
        size: Size.infinite,
      ),
    );
  }
}

class SwScanBand extends StatefulWidget {
  const SwScanBand({super.key, this.color = AppUIv1.accentCyan});

  final Color color;

  @override
  State<SwScanBand> createState() => _SwScanBandState();
}

class _SwScanBandState extends State<SwScanBand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppUIv1.durationScan,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _ScanBandPainter(
              progress: _controller.value,
              color: widget.color,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _ScanBandPainter extends CustomPainter {
  const _ScanBandPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()
      ..color = AppUIv1.surfaceMuted
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), track);
    final width = size.width * 0.34;
    final start = (size.width + width) * progress - width;
    final rect = Rect.fromLTWH(start, 0, width, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0.85),
          AppUIv1.accentTeal.withValues(alpha: 0.80),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(AppUIv1.radiusFull),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanBandPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _MiniGraphPainter extends CustomPainter {
  const _MiniGraphPainter({required this.color, required this.values});

  final Color color;
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - (size.height * values[i].clamp(0, 1));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          colors: [color.withValues(alpha: 0.22), Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniGraphPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.values != values;
  }
}

class SwReveal extends StatelessWidget {
  const SwReveal({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppUIv1.durationSlow + delay,
      curve: AppUIv1.curveEnter,
      builder: (context, value, child) {
        final opacity = value.clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, (1 - opacity) * 12),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

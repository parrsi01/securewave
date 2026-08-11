import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'sw_theme.dart';

/// ---------------------------------------------------------------------------
/// Brand mark
/// ---------------------------------------------------------------------------

/// Rounded-square badge containing a shield outline and a signal wave.
class SwLogo extends StatelessWidget {
  const SwLogo({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _SwLogoPainter()),
    );
  }
}

class _SwLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final radius = s * 0.5;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, s, s),
        Radius.circular(radius.clamp(0.0, s * 0.5)),
      ),
      Paint()..color = SwColors.primaryStrong,
    );

    final stroke = Paint()
      ..color = SwColors.onPrimary
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(1.0, s * 2 / 24);

    final shield = Path()
      ..moveTo(s * 0.50, s * 0.22)
      ..lineTo(s * 0.74, s * 0.33)
      ..quadraticBezierTo(s * 0.74, s * 0.64, s * 0.50, s * 0.80)
      ..quadraticBezierTo(s * 0.26, s * 0.64, s * 0.26, s * 0.33)
      ..close();
    canvas.drawPath(shield, stroke);

    final wave = Path();
    const samples = 24;
    const left = 0.335;
    const right = 0.665;
    for (var i = 0; i <= samples; i++) {
      final t = i / samples;
      final x = (left + (right - left) * t) * s;
      final y = (0.515 - 0.052 * math.sin(t * math.pi * 3)) * s;
      if (i == 0) {
        wave.moveTo(x, y);
      } else {
        wave.lineTo(x, y);
      }
    }
    canvas.drawPath(
      wave,
      Paint()
        ..color = SwColors.onPrimary
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = math.max(0.9, s * 1.8 / 24),
    );
  }

  @override
  bool shouldRepaint(covariant _SwLogoPainter oldDelegate) => false;
}

/// ---------------------------------------------------------------------------
/// Line icons
/// ---------------------------------------------------------------------------

enum SwIconKind { home, account, pulse, power }

class SwIcon extends StatelessWidget {
  const SwIcon({
    super.key,
    required this.kind,
    this.size = 20,
    this.color = SwColors.textSecondary,
    this.strokeWidth = 1.8,
  });

  final SwIconKind kind;
  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _SwIconPainter(
          kind: kind,
          color: color,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _SwIconPainter extends CustomPainter {
  _SwIconPainter({
    required this.kind,
    required this.color,
    required this.strokeWidth,
  });

  final SwIconKind kind;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth * s / 20;

    switch (kind) {
      case SwIconKind.home:
        canvas.drawPath(
          Path()
            ..moveTo(s * 0.14, s * 0.46)
            ..lineTo(s * 0.50, s * 0.16)
            ..lineTo(s * 0.86, s * 0.46),
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(s * 0.24, s * 0.46, s * 0.76, s * 0.84),
            Radius.circular(s * 0.08),
          ),
          paint,
        );
      case SwIconKind.account:
        canvas.drawCircle(Offset(s * 0.5, s * 0.34), s * 0.16, paint);
        canvas.drawArc(
          Rect.fromLTRB(s * 0.20, s * 0.56, s * 0.80, s * 1.04),
          math.pi,
          math.pi,
          false,
          paint,
        );
      case SwIconKind.pulse:
        canvas.drawPath(
          Path()
            ..moveTo(s * 0.12, s * 0.52)
            ..lineTo(s * 0.32, s * 0.52)
            ..lineTo(s * 0.44, s * 0.26)
            ..lineTo(s * 0.58, s * 0.76)
            ..lineTo(s * 0.68, s * 0.52)
            ..lineTo(s * 0.88, s * 0.52),
          paint,
        );
      case SwIconKind.power:
        canvas.drawLine(
          Offset(s * 0.5, s * 0.16),
          Offset(s * 0.5, s * 0.46),
          paint,
        );
        canvas.drawArc(
          Rect.fromCircle(center: Offset(s * 0.5, s * 0.55), radius: s * 0.30),
          -math.pi / 2 + 0.62,
          math.pi * 2 - 1.24,
          false,
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _SwIconPainter old) =>
      old.color != color || old.kind != kind || old.strokeWidth != strokeWidth;
}

/// ---------------------------------------------------------------------------
/// Navigation
/// ---------------------------------------------------------------------------

class SwDestination {
  const SwDestination({
    required this.label,
    required this.icon,
  });

  final String label;
  final SwIconKind icon;
}

/// Fixed-width left navigation column used on regular desktop widths.
class SwNavRail extends StatelessWidget {
  const SwNavRail({
    super.key,
    required this.destinations,
    required this.index,
    required this.onSelected,
    required this.connected,
  });

  final List<SwDestination> destinations;
  final int index;
  final ValueChanged<int> onSelected;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: SwLayout.railWidth,
      decoration: const BoxDecoration(
        color: SwColors.surface,
        border: Border(right: BorderSide(color: SwColors.border)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: SwSpacing.md),
            const SwLogo(size: 34),
            const SizedBox(height: SwSpacing.md),
            for (var i = 0; i < destinations.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: SwSpacing.xs),
                child: _RailItem(
                  destination: destinations[i],
                  selected: index == i,
                  onTap: () => onSelected(i),
                ),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: SwSpacing.md),
              child: Column(
                children: [
                  SwStatusDot(active: connected),
                  const SizedBox(height: 6),
                  Text(
                    connected ? 'ACTIVE' : 'OFFLINE',
                    style: SwType.micro.copyWith(
                      color: connected
                          ? SwColors.primaryStrong
                          : SwColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final SwDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? SwColors.primaryStrong : SwColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SwRadius.md),
        child: AnimatedContainer(
          duration: SwMotion.fast,
          curve: SwMotion.curve,
          width: 72,
          height: 56,
          decoration: BoxDecoration(
            color: selected ? SwColors.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(SwRadius.md),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SwIcon(kind: destination.icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(
                destination.label.toUpperCase(),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: SwType.micro.copyWith(color: color, letterSpacing: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Status primitives
/// ---------------------------------------------------------------------------

class SwStatusDot extends StatelessWidget {
  const SwStatusDot({super.key, required this.active, this.size = 8});

  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: SwMotion.fast,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? SwColors.primaryStrong : SwColors.idle,
      ),
    );
  }
}

class SwStatusPill extends StatelessWidget {
  const SwStatusPill({
    super.key,
    required this.text,
    this.success = false,
  });

  final String text;
  final bool success;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: SwMotion.medium,
      curve: SwMotion.curve,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: success ? SwColors.primarySoft : SwColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(SwRadius.pill),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: SwType.label.copyWith(
          letterSpacing: 0.3,
          color: success ? SwColors.primaryStrong : SwColors.textSecondary,
        ),
      ),
    );
  }
}

enum SwNoticeTone { info, warning, error }

class SwNotice extends StatelessWidget {
  const SwNotice({
    super.key,
    required this.title,
    this.message,
    this.tone = SwNoticeTone.info,
  });

  final String title;
  final String? message;
  final SwNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    // Text stays on the near-black ink so every tone clears WCAG AA; the tone
    // itself is carried by the tint and the accent bar, never by text colour.
    final (Color bg, Color accent) = switch (tone) {
      SwNoticeTone.info => (SwColors.surfaceSecondary, SwColors.idle),
      SwNoticeTone.warning => (SwColors.warningSoft, SwColors.warning),
      SwNoticeTone.error => (SwColors.errorSoft, SwColors.error),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 18, 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(SwRadius.md),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: SwType.body.copyWith(
              color: SwColors.textPrimary,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              message!,
              style: SwType.footnote.copyWith(color: SwColors.textPrimary),
            ),
          ],
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Connect control — the primary action of the application.
/// ---------------------------------------------------------------------------

class SwConnectButton extends StatelessWidget {
  const SwConnectButton({
    super.key,
    required this.connected,
    required this.busy,
    required this.label,
    required this.onPressed,
  });

  final bool connected;
  final bool busy;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null && !busy;

    return SizedBox.square(
      dimension: SwLayout.connectWrap,
      child: Center(
        child: Semantics(
          button: true,
          enabled: onPressed != null,
          label: label,
          child: Opacity(
            opacity: disabled ? 0.45 : 1,
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: AnimatedContainer(
                duration: SwMotion.fast,
                curve: SwMotion.curve,
                width: SwLayout.connectCircle,
                height: SwLayout.connectCircle,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected ? SwColors.primaryStrong : SwColors.surface,
                  border: connected
                      ? null
                      : Border.all(color: SwColors.border, width: 2),
                  boxShadow: connected ? SwShadow.connected : SwShadow.card,
                ),
                child: AnimatedSwitcher(
                  duration: SwMotion.fast,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: Column(
                    key: ValueKey('${connected}_$busy'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (busy)
                        SizedBox.square(
                          dimension: 34,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: connected
                                ? SwColors.onPrimary
                                : SwColors.primaryStrong,
                          ),
                        )
                      else
                        SwIcon(
                          kind: SwIconKind.power,
                          size: 44,
                          strokeWidth: 2.1,
                          color: connected
                              ? SwColors.onPrimary
                              : SwColors.textSecondary,
                        ),
                      const SizedBox(height: 14),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: SwType.connectLabel.copyWith(
                          color: connected
                              ? SwColors.onPrimary
                              : SwColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Surfaces
/// ---------------------------------------------------------------------------

class SwPanel extends StatelessWidget {
  const SwPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: SwColors.surface,
        border: Border.all(color: SwColors.border),
        borderRadius: BorderRadius.circular(SwRadius.lg),
      ),
      child: child,
    );
  }
}

class SwSectionLabel extends StatelessWidget {
  const SwSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(text.toUpperCase(), style: SwType.label),
    );
  }
}

class SwStat {
  const SwStat({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;
}

/// Panel containing a responsive grid of labelled statistics.
class SwInfoCard extends StatelessWidget {
  const SwInfoCard({super.key, required this.stats});

  final List<SwStat> stats;

  @override
  Widget build(BuildContext context) {
    return SwPanel(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoUp = constraints.maxWidth >= 360;
          final columns = twoUp ? 2 : 1;
          final rows = <Widget>[];
          for (var i = 0; i < stats.length; i += columns) {
            final slice = stats.skip(i).take(columns).toList();
            rows.add(
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = 0; j < columns; j++)
                    Expanded(
                      child: j < slice.length
                          ? _StatCell(
                              stat: slice[j],
                              padRight: j < columns - 1,
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            );
            if (i + columns < stats.length) {
              rows.add(const SizedBox(height: 24));
            }
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows,
          );
        },
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.stat, this.padRight = false});

  final SwStat stat;
  final bool padRight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Gutter between columns only, so the card's side padding stays even.
      padding: EdgeInsets.only(right: padRight ? 22 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(stat.label.toUpperCase(), style: SwType.label),
          const SizedBox(height: 6),
          Text(
            stat.value,
            style: SwType.statValue.copyWith(
              color: stat.highlight
                  ? SwColors.primaryStrong
                  : SwColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Settings-style list container. Rows are separated by hairlines.
class SwRowPanel extends StatelessWidget {
  const SwRowPanel({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      children.add(rows[i]);
      if (i != rows.length - 1) {
        children.add(const Divider(height: 1, color: SwColors.border));
      }
    }
    return SwPanel(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SwRadius.lg),
        child: Column(children: children),
      ),
    );
  }
}

class SwRow extends StatelessWidget {
  const SwRow({
    super.key,
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
  });

  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Row(
        children: [
          // Intentionally not flexible: labels are short fixed strings, and
          // giving them a flex slot would cap the value at half the row and
          // ellipsise it against empty space.
          Text(
            label,
            style: SwType.body.copyWith(
              color: SwColors.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value!,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: SwType.body.copyWith(height: 1.3),
              ),
            ),
          ] else
            const Spacer(),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}

/// ---------------------------------------------------------------------------
/// Segmented control (authentication mode switch)
/// ---------------------------------------------------------------------------

class SwSegmentedControl extends StatelessWidget {
  const SwSegmentedControl({
    super.key,
    required this.segments,
    required this.index,
    required this.onChanged,
  });

  final List<String> segments;
  final int index;

  /// Null disables the control, matching the button convention.
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: SwColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(SwRadius.md),
        ),
        child: Row(
          children: [
            for (var i = 0; i < segments.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: enabled
                      ? HitTestBehavior.opaque
                      : HitTestBehavior.deferToChild,
                  onTap: enabled ? () => onChanged!(i) : null,
                  child: AnimatedContainer(
                    duration: SwMotion.fast,
                    curve: SwMotion.curve,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: index == i ? SwColors.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(SwRadius.sm + 2),
                      boxShadow: index == i ? SwShadow.segment : null,
                    ),
                    child: Text(
                      segments[i],
                      style: SwType.button.copyWith(
                        color: index == i
                            ? SwColors.textPrimary
                            : SwColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small filled check used by the authentication feature list.
class SwCheckBullet extends StatelessWidget {
  const SwCheckBullet({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: SwColors.primaryStrong,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 12,
              color: SwColors.onPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: SwType.body.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: SwColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

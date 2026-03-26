import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

/// Primary accent CTA button with a softened glow effect.
///
/// States:
///   - Normal: softened orchid -> iris -> blue gradient + dark text
///   - Hover/pressed: glow ring amplified via AnimatedContainer BoxShadow
///   - Connecting: slow pulse animation on the outer glow ring
///   - Disabled: ghosted neon fill, no glow
///
/// Use [NeonOutlinedButton] for secondary actions.
class NeonButton extends StatefulWidget {
  const NeonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isConnecting = false,
    this.isDestructive = false,
    this.width,
    this.height = AppTokens.buttonHeightM,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// When true, adds a pulsing animation to the glow ring (connecting state).
  final bool isConnecting;

  /// When true, uses the destructive error accent instead of the primary glow.
  final bool isDestructive;

  final double? width;
  final double height;

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  bool _hovered = false;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: AppTokens.durationPulse,
    );
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: AppTokens.curvePulse),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(NeonButton old) {
    super.didUpdateWidget(old);
    if (old.isConnecting != widget.isConnecting) _syncPulse();
  }

  void _syncPulse() {
    if (widget.isConnecting) {
      _pulseCtrl.repeat(reverse: true);
    } else {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Color get _accentColor => widget.isDestructive
      ? HtbColors.statusDisconnected
      : HtbColors.accentPrimary;

  Color get _glowBase =>
      widget.isDestructive ? HtbColors.glowRed : HtbColors.glowSecondary;

  Gradient get _backgroundGradient => widget.isDestructive
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [HtbColors.statusDisconnected, HtbColors.statusErrorDeep],
        )
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HtbColors.accentSecondaryMuted,
            HtbColors.accentSecondary,
            HtbColors.accentPrimary,
          ],
        );

  List<BoxShadow> _buildShadow(double pulseValue) {
    if (widget.onPressed == null) return const [];
    if (_pressed || _hovered || widget.isConnecting) {
      final intensity =
          widget.isConnecting ? pulseValue : (_pressed ? 1.0 : 0.6);
      return [
        BoxShadow(
          color: _glowBase.withValues(alpha: 0.3 * intensity),
          blurRadius: 20,
          spreadRadius: 1,
        ),
        BoxShadow(
          color: _accentColor.withValues(alpha: 0.16 * intensity),
          blurRadius: 10,
          spreadRadius: 0,
        ),
      ];
    }
    return [
      BoxShadow(
        color: _glowBase.withValues(alpha: 0.12),
        blurRadius: 8,
        spreadRadius: 0,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, _) {
        return AnimatedContainer(
          duration: AppTokens.durationFast,
          curve: AppTokens.curveDefault,
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: AppTokens.brMedium,
            boxShadow: _buildShadow(_pulseAnim.value),
          ),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Semantics(
              button: true,
              enabled: !disabled,
              label: widget.label,
              child: GestureDetector(
                onTapDown:
                    disabled ? null : (_) => setState(() => _pressed = true),
                onTapUp:
                    disabled ? null : (_) => setState(() => _pressed = false),
                onTapCancel: () => setState(() => _pressed = false),
                child: AnimatedScale(
                  scale: _pressed ? 0.97 : 1.0,
                  duration: AppTokens.durationFast,
                  curve: AppTokens.curveDefault,
                  child: Material(
                    color: Colors.transparent,
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: AppTokens.brMedium,
                        gradient: disabled ? null : _backgroundGradient,
                        color: disabled
                            ? _accentColor.withValues(alpha: 0.12)
                            : null,
                        border: Border.all(
                          color: disabled
                              ? HtbColors.border
                              : HtbColors.textPrimary.withValues(alpha: 0.08),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: AppTokens.brMedium,
                        onTap: widget.onPressed,
                        child: ConstrainedBox(
                          constraints: widget.width == null
                              ? BoxConstraints(
                                  minWidth: AppTokens.buttonMinWidth,
                                  minHeight: widget.height,
                                )
                              : BoxConstraints.tightFor(
                                  width: widget.width,
                                  height: widget.height,
                                ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTokens.paddingL,
                              vertical: AppTokens.paddingS,
                            ),
                            child: Center(
                              child: DefaultTextStyle(
                                style: AppTypography.textTheme()
                                        .labelLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.8,
                                          color: disabled
                                              ? HtbColors.textTertiary
                                              : HtbColors.textInverse,
                                        ) ??
                                    const TextStyle(),
                                child: IconTheme(
                                  data: IconThemeData(
                                    color: disabled
                                        ? HtbColors.textTertiary
                                        : HtbColors.textInverse,
                                    size: AppTokens.iconS,
                                  ),
                                  child: _ButtonContent(
                                    label: widget.label,
                                    icon: widget.icon,
                                    isConnecting: widget.isConnecting,
                                    accentColor: disabled
                                        ? HtbColors.textTertiary
                                        : HtbColors.textInverse,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Secondary outlined button with shared accent border and hover glow.
class NeonOutlinedButton extends StatefulWidget {
  const NeonOutlinedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.accentColor = HtbColors.accentPrimary,
    this.width,
    this.height = AppTokens.buttonHeightM,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color accentColor;
  final double? width;
  final double height;

  @override
  State<NeonOutlinedButton> createState() => _NeonOutlinedButtonState();
}

class _NeonOutlinedButtonState extends State<NeonOutlinedButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final glowOpacity = _pressed
        ? 0.5
        : _hovered
            ? 0.3
            : 0.0;

    return AnimatedContainer(
      duration: AppTokens.durationFast,
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: AppTokens.brMedium,
        boxShadow: glowOpacity > 0
            ? [
                BoxShadow(
                  color: widget.accentColor.withValues(alpha: glowOpacity),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : const [],
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1.0,
            duration: AppTokens.durationFast,
            child: OutlinedButton(
              onPressed: widget.onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    disabled ? HtbColors.textTertiary : widget.accentColor,
                minimumSize: widget.width == null
                    ? Size(
                        AppTokens.buttonMinWidth,
                        widget.height,
                      )
                    : Size(widget.width!, widget.height),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppTokens.brMedium,
                ),
                side: BorderSide(
                  color: disabled
                      ? HtbColors.border
                      : _hovered
                          ? widget.accentColor
                          : widget.accentColor.withValues(alpha: 0.6),
                  width: AppTokens.neonBorderWidth,
                ),
                backgroundColor: _pressed
                    ? widget.accentColor.withValues(alpha: 0.1)
                    : _hovered
                        ? widget.accentColor.withValues(alpha: 0.05)
                        : Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.paddingL,
                ),
                textStyle: AppTypography.textTheme().labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
              ),
              child: _ButtonContent(
                label: widget.label,
                icon: widget.icon,
                isConnecting: false,
                accentColor:
                    disabled ? HtbColors.textTertiary : widget.accentColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.isConnecting,
    required this.accentColor,
    this.icon,
  });

  final String label;
  final bool isConnecting;
  final Color accentColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (isConnecting) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: accentColor,
            ),
          ),
          const SizedBox(width: AppTokens.gapS),
          Text(label),
        ],
      );
    }
    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppTokens.iconS),
          const SizedBox(width: AppTokens.gapS),
          Text(label),
        ],
      );
    }
    return Text(label);
  }
}

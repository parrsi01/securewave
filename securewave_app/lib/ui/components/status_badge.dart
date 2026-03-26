import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

/// VPN connection status states for [StatusBadge].
enum StatusBadgeState {
  connected,
  disconnected,
  connecting,
  warning,
  error,
}

/// Compact status badge — dot indicator + label + optional glow ring.
///
/// Color-coded per [StatusBadgeState]:
///   - connected    : primary accent
///   - disconnected : red
///   - connecting   : amber (animated dot pulse)
///   - warning      : orange
///   - error        : red (brighter than disconnected)
///
/// The dot pulses continuously when [state] == [StatusBadgeState.connecting].
class StatusBadge extends StatefulWidget {
  const StatusBadge({
    super.key,
    required this.state,
    this.label,
    this.showGlow = true,
    this.compact = false,
  });

  final StatusBadgeState state;

  /// Override the default label derived from [state].
  final String? label;

  /// Draw a subtle color glow behind the container.
  final bool showGlow;

  /// Compact mode: dot only, no label, smaller padding.
  final bool compact;

  @override
  State<StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<StatusBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dotCtrl;
  late final Animation<double> _dotScale;
  late final Animation<double> _dotOpacity;

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _dotScale = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _dotCtrl, curve: Curves.easeInOut),
    );
    _dotOpacity = Tween<double>(begin: 1.0, end: 0.5).animate(
      CurvedAnimation(parent: _dotCtrl, curve: Curves.easeInOut),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(StatusBadge old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.state == StatusBadgeState.connecting) {
      _dotCtrl.repeat(reverse: true);
    } else {
      _dotCtrl.stop();
      _dotCtrl.value = 0;
    }
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    super.dispose();
  }

  Color get _accentColor => switch (widget.state) {
        StatusBadgeState.connected => HtbColors.statusConnected,
        StatusBadgeState.disconnected => HtbColors.statusDisconnected,
        StatusBadgeState.connecting => HtbColors.statusConnecting,
        StatusBadgeState.warning => HtbColors.statusWarning,
        StatusBadgeState.error => HtbColors.statusError,
      };

  String get _defaultLabel => switch (widget.state) {
        StatusBadgeState.connected => 'Connected',
        StatusBadgeState.disconnected => 'Disconnected',
        StatusBadgeState.connecting => 'Connecting',
        StatusBadgeState.warning => 'Warning',
        StatusBadgeState.error => 'Error',
      };

  List<BoxShadow> get _glow => widget.showGlow
      ? [
          BoxShadow(
            color: _accentColor.withValues(alpha: 0.25),
            blurRadius: 12,
            spreadRadius: 0,
          ),
        ]
      : const [];

  @override
  Widget build(BuildContext context) {
    final label = widget.label ?? _defaultLabel;
    final color = _accentColor;

    return AnimatedContainer(
      duration: AppTokens.durationNormal,
      padding: widget.compact
          ? const EdgeInsets.all(AppTokens.paddingXS)
          : const EdgeInsets.symmetric(
              horizontal: AppTokens.sp12,
              vertical: AppTokens.sp8,
            ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppTokens.brPill,
        border: Border.all(
          color: color.withValues(alpha: 0.30),
          width: AppTokens.borderWidth,
        ),
        boxShadow: _glow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated dot
          AnimatedBuilder(
            animation: _dotCtrl,
            builder: (context, _) {
              return Transform.scale(
                scale: _dotScale.value,
                child: Opacity(
                  opacity: _dotOpacity.value,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.6),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          if (!widget.compact) ...[
            const SizedBox(width: AppTokens.sp8),
            Text(
              label,
              style: AppTypography.textTheme().labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

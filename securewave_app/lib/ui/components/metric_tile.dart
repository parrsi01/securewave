import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import 'glass_panel.dart';

/// Single VPN metric tile — label, monospace value, optional unit.
///
/// Backed by [HtbGlassPanel]. Designed for a 2- or 4-up grid layout
/// showing stats like download speed, ping, uptime, and assigned IP.
///
/// Value is always rendered in monospace ([AppTypography.monoLarge]).
/// Label and unit use the standard sans-serif stack.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.accentColor,
    this.isHighlighted = false,
  });

  /// Short label shown above the value, e.g. "Download", "Ping".
  final String label;

  /// The metric value, e.g. "48.3", "12", "02:14:07".
  final String value;

  /// Unit suffix rendered in small monospace, e.g. "Mbps", "ms".
  final String? unit;

  /// Optional leading icon for the tile header.
  final IconData? icon;

  /// Accent color for the icon and value text. Defaults to [HtbColors.textMono].
  final Color? accentColor;

  /// When true, adds a neon border glow to the glass panel.
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? HtbColors.textMono;

    return HtbGlassPanel(
      glowColor: isHighlighted ? accent : null,
      glowIntensity: 0.5,
      borderColor: isHighlighted
          ? accent.withValues(alpha: 0.35)
          : HtbColors.glassBorderDefault,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.paddingM,
        vertical: AppTokens.sp12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header row: icon + label ──────────────────────────────────────
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppTokens.iconS, color: accent),
                const SizedBox(width: AppTokens.gapXS),
              ],
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: AppTypography.textTheme().labelSmall?.copyWith(
                    color: HtbColors.textTertiary,
                    letterSpacing: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: AppTokens.sp8),

          // ── Value row ─────────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: AppTypography.monoLarge.copyWith(color: accent),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: AppTokens.sp4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    unit!,
                    style: AppTypography.monoLabel,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact single-row variant for inline metric display.
class MetricTileInline extends StatelessWidget {
  const MetricTileInline({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.accentColor,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? HtbColors.textMono;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: AppTokens.iconXS, color: HtbColors.textTertiary),
          const SizedBox(width: AppTokens.gapXS),
        ],
        Text(
          '$label:',
          style: AppTypography.monoSmall.copyWith(
            color: HtbColors.textTertiary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: AppTokens.sp4),
        Text(
          value,
          style: AppTypography.monoSmall.copyWith(color: accent),
        ),
        if (unit != null) ...[
          const SizedBox(width: 2),
          Text(
            unit!,
            style: AppTypography.monoLabel,
          ),
        ],
      ],
    );
  }
}

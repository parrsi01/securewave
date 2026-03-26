import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';

/// Server entry for the VPN server selection list.
///
/// Layout:
///   [flag/region icon] [server name + region] [ping] [load bar]
///
/// When [isSelected] is true:
///   - Primary accent left rail
///   - Accent glow background fill
///   - Neon border
///
/// [loadFraction] is 0.0–1.0. Color transitions:
///   - 0.0–0.5  : primary accent
///   - 0.5–0.75 : amber
///   - 0.75–1.0 : red
class ServerListTile extends StatelessWidget {
  const ServerListTile({
    super.key,
    required this.serverId,
    required this.serverName,
    required this.regionLabel,
    this.countryCode,
    this.flagWidget,
    this.pingMs,
    this.loadFraction = 0.0,
    this.isSelected = false,
    this.isRecommended = false,
    this.onTap,
  });

  /// Unique server identifier — used as ValueKey.
  final String serverId;

  final String serverName;
  final String regionLabel;

  /// ISO 3166-1 alpha-2 country code (e.g. "US", "DE"). Used as fallback
  /// display when [flagWidget] is null.
  final String? countryCode;

  /// Custom flag or region icon widget. Falls back to countryCode text badge.
  final Widget? flagWidget;

  /// Round-trip ping in milliseconds. Null = not measured yet.
  final int? pingMs;

  /// Server load 0.0–1.0.
  final double loadFraction;

  final bool isSelected;

  /// Shows a "Best" badge next to the server name.
  final bool isRecommended;

  final VoidCallback? onTap;

  // ── Helpers ─────────────────────────────────────────────────────────────

  Color _loadColor() {
    if (loadFraction < 0.50) return HtbColors.loadLow;
    if (loadFraction < 0.75) return HtbColors.loadMedium;
    return HtbColors.loadHigh;
  }

  Color _pingColor() {
    if (pingMs == null) return HtbColors.textTertiary;
    if (pingMs! < 60) return HtbColors.statusConnected;
    if (pingMs! < 120) return HtbColors.statusConnecting;
    return HtbColors.statusDisconnected;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppTokens.durationNormal,
      curve: AppTokens.curveDefault,
      margin: const EdgeInsets.symmetric(
        horizontal: AppTokens.sp8,
        vertical: AppTokens.sp4,
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? HtbColors.accentPrimaryGhost
            : HtbColors.bg1,
        borderRadius: AppTokens.brCard,
        border: Border.all(
          color: isSelected
              ? HtbColors.glassBorderNeon
              : HtbColors.border,
          width: isSelected
              ? AppTokens.neonBorderWidth
              : AppTokens.borderWidth,
        ),
        boxShadow: isSelected
            ? AppTokens.glowPrimarySoft
            : const [],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppTokens.brCard,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppTokens.brCard,
          splashColor: HtbColors.accentPrimaryGhost,
          highlightColor: HtbColors.accentPrimaryHover,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.paddingM,
              vertical: AppTokens.sp12,
            ),
            child: Row(
              children: [
                // ── Left accent bar (selected) ──────────────────────────
                AnimatedContainer(
                  duration: AppTokens.durationFast,
                  width: 3,
                  height: 40,
                  margin: const EdgeInsets.only(right: AppTokens.sp12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? HtbColors.accentPrimary
                        : Colors.transparent,
                    borderRadius: AppTokens.brPill,
                    boxShadow: isSelected ? AppTokens.glowPrimarySoft : null,
                  ),
                ),

                // ── Flag / region icon ──────────────────────────────────
                _FlagSlot(
                  flagWidget: flagWidget,
                  countryCode: countryCode,
                  isSelected: isSelected,
                ),
                const SizedBox(width: AppTokens.sp12),

                // ── Server name + region ────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              serverName,
                              style: AppTypography.textTheme()
                                  .titleSmall
                                  ?.copyWith(
                                    color: isSelected
                                        ? HtbColors.accentPrimary
                                        : HtbColors.textPrimary,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isRecommended) ...[
                            const SizedBox(width: AppTokens.sp4),
                            _BestBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppTokens.sp4),
                      Text(
                        regionLabel,
                        style: AppTypography.textTheme().bodySmall?.copyWith(
                          color: HtbColors.textTertiary,
                          letterSpacing: 0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: AppTokens.sp12),

                // ── Ping + load bar ─────────────────────────────────────
                _MetricsColumn(
                  pingMs: pingMs,
                  pingColor: _pingColor(),
                  loadFraction: loadFraction,
                  loadColor: _loadColor(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _FlagSlot extends StatelessWidget {
  const _FlagSlot({
    required this.flagWidget,
    required this.countryCode,
    required this.isSelected,
  });

  final Widget? flagWidget;
  final String? countryCode;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    if (flagWidget != null) {
      return SizedBox(width: 32, height: 24, child: flagWidget);
    }
    if (countryCode != null) {
      return Container(
        width: 32,
        height: 24,
        decoration: BoxDecoration(
          color: isSelected ? HtbColors.accentPrimaryGhost : HtbColors.bg2,
          borderRadius: AppTokens.brSmall,
          border: Border.all(
            color: isSelected ? HtbColors.glassBorderNeon : HtbColors.border,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          countryCode!.toUpperCase(),
          style: AppTypography.monoSmall.copyWith(
            fontSize: 10,
            color: isSelected ? HtbColors.accentPrimary : HtbColors.textSecondary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );
    }
    return const Icon(
      Icons.dns_rounded,
      size: AppTokens.iconM,
      color: HtbColors.textTertiary,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MetricsColumn extends StatelessWidget {
  const _MetricsColumn({
    required this.pingMs,
    required this.pingColor,
    required this.loadFraction,
    required this.loadColor,
  });

  final int? pingMs;
  final Color pingColor;
  final double loadFraction;
  final Color loadColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ping label
          Text(
            pingMs != null ? '${pingMs}ms' : '--',
            style: AppTypography.monoSmall.copyWith(
              color: pingColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTokens.sp4),
          // Load bar
          _LoadBar(fraction: loadFraction, color: loadColor),
          const SizedBox(height: 2),
          Text(
            '${(loadFraction * 100).round()}%',
            style: AppTypography.monoLabel.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _LoadBar extends StatelessWidget {
  const _LoadBar({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 4,
          width: constraints.maxWidth,
          decoration: const BoxDecoration(
            color: HtbColors.bg3,
            borderRadius: AppTokens.brPill,
          ),
          child: FractionallySizedBox(
            widthFactor: fraction.clamp(0.0, 1.0),
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: AppTokens.durationNormal,
              decoration: BoxDecoration(
                color: color,
                borderRadius: AppTokens.brPill,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _BestBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.sp4,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: HtbColors.accentPrimaryGhost,
        borderRadius: AppTokens.brPill,
        border: Border.all(
          color: HtbColors.glassBorderNeon,
          width: AppTokens.borderWidth,
        ),
      ),
      child: Text(
        'BEST',
        style: AppTypography.monoLabel.copyWith(
          color: HtbColors.accentPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 9,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/models/server_region.dart';
import '../../../ui/design/app_animations.dart';
import '../../../ui/design/app_colors.dart';
import '../../../ui/design/app_spacing.dart';

/// Returns a Unicode flag emoji for the given country name.
String countryFlag(String? country) {
  const map = {
    'United States': '\u{1f1fa}\u{1f1f8}',
    'Germany': '\u{1f1e9}\u{1f1ea}',
    'Netherlands': '\u{1f1f3}\u{1f1f1}',
    'United Kingdom': '\u{1f1ec}\u{1f1e7}',
    'France': '\u{1f1eb}\u{1f1f7}',
    'Japan': '\u{1f1ef}\u{1f1f5}',
    'Singapore': '\u{1f1f8}\u{1f1ec}',
    'Australia': '\u{1f1e6}\u{1f1fa}',
    'Canada': '\u{1f1e8}\u{1f1e6}',
    'Sweden': '\u{1f1f8}\u{1f1ea}',
    'Switzerland': '\u{1f1e8}\u{1f1ed}',
    'Brazil': '\u{1f1e7}\u{1f1f7}',
    'India': '\u{1f1ee}\u{1f1f3}',
    'South Korea': '\u{1f1f0}\u{1f1f7}',
    'Ireland': '\u{1f1ee}\u{1f1ea}',
    'Italy': '\u{1f1ee}\u{1f1f9}',
    'Spain': '\u{1f1ea}\u{1f1f8}',
    'Poland': '\u{1f1f5}\u{1f1f1}',
    'Norway': '\u{1f1f3}\u{1f1f4}',
    'Finland': '\u{1f1eb}\u{1f1ee}',
    'Denmark': '\u{1f1e9}\u{1f1f0}',
    'Austria': '\u{1f1e6}\u{1f1f9}',
    'Belgium': '\u{1f1e7}\u{1f1ea}',
    'Czech Republic': '\u{1f1e8}\u{1f1ff}',
    'Portugal': '\u{1f1f5}\u{1f1f9}',
    'Romania': '\u{1f1f7}\u{1f1f4}',
    'South Africa': '\u{1f1ff}\u{1f1e6}',
    'Mexico': '\u{1f1f2}\u{1f1fd}',
    'Argentina': '\u{1f1e6}\u{1f1f7}',
    'Chile': '\u{1f1e8}\u{1f1f1}',
    'New Zealand': '\u{1f1f3}\u{1f1ff}',
    'Hong Kong': '\u{1f1ed}\u{1f1f0}',
    'Taiwan': '\u{1f1f9}\u{1f1fc}',
    'Israel': '\u{1f1ee}\u{1f1f1}',
    'Turkey': '\u{1f1f9}\u{1f1f7}',
    'Ukraine': '\u{1f1fa}\u{1f1e6}',
    'United Arab Emirates': '\u{1f1e6}\u{1f1ea}',
  };
  return map[country] ?? '\u{1f30d}';
}

Color _latencyColor(int? ms) {
  if (ms == null) return AppColors.inkSoft;
  if (ms < 50) return AppColors.success;
  if (ms < 100) return AppColors.secondary;
  return AppColors.error;
}

/// Server tile — v2.
///
/// Clean, touch-friendly tile with:
/// - Country flag leading
/// - Latency bar + ms value
/// - Animated selection highlight
/// - Favorite star toggle
/// - Premium lock badge for servers requiring a paid subscription
class ServerTile extends StatelessWidget {
  const ServerTile({
    super.key,
    required this.server,
    required this.isSelected,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
    this.isPremiumLocked = false,
  });

  final ServerRegion server;
  final bool isSelected;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  /// When true the server requires a premium subscription the user does not
  /// have. The tile is shown with a lock badge and tapping shows an upgrade
  /// prompt instead of selecting the server.
  final bool isPremiumLocked;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.primaryBright : AppColors.primary;
    final mutedColor = isDark ? AppColors.darkInkSoft : AppColors.inkSoft;
    final subtitle = [server.city, server.country]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(', ');

    return Semantics(
      label: isPremiumLocked
          ? 'Premium server: ${server.name}, $subtitle. Requires premium subscription.'
          : 'Server: ${server.name}, $subtitle. ${server.latencyMs != null ? 'Latency: ${server.latencyMs}ms.' : ''}',
      child: AnimatedContainer(
        duration: AppAnimations.durationFast,
        color: isSelected && !isPremiumLocked
            ? primaryColor.withValues(alpha: isDark ? 0.12 : 0.06)
            : Colors.transparent,
        child: ListTile(
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              Text(
                countryFlag(server.country),
                style: TextStyle(
                  fontSize: 22,
                  color: isPremiumLocked
                      ? null
                      : null,
                ),
              ),
              if (isPremiumLocked)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkSurface
                            : AppColors.surface,
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      size: 9,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          title: Text(
            server.name,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: isSelected && !isPremiumLocked
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: isPremiumLocked
                      ? mutedColor
                      : isSelected
                          ? primaryColor
                          : null,
                ),
          ),
          subtitle: subtitle.isNotEmpty
              ? Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isPremiumLocked ? mutedColor : null,
                      ),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPremiumLocked) ...[
                // ── Premium badge ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space2,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.15),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusFull),
                    border: Border.all(
                      color: AppColors.secondary.withValues(alpha: 0.40),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    'Premium',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                  ),
                ),
              ] else ...[
                // ── Latency indicator ──────────────────────────────────
                if (server.latencyMs != null) ...[
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: SizedBox(
                          width: 36,
                          height: 4,
                          child: LinearProgressIndicator(
                            value: (server.latencyMs!.clamp(0, 200) / 200)
                                .toDouble(),
                            backgroundColor: isDark
                                ? AppColors.darkBorder
                                : AppColors.border,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _latencyColor(server.latencyMs),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      // ms label
                      Text(
                        '${server.latencyMs}ms',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _latencyColor(server.latencyMs),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.space2),
                ],

                // ── Favorite toggle ────────────────────────────────────
                AnimatedSwitcher(
                  duration: AppAnimations.favoriteToggle,
                  switchInCurve: AppAnimations.curveEnter,
                  child: IconButton(
                    key: ValueKey(isFavorite),
                    icon: Icon(
                      isFavorite
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: isFavorite
                          ? AppColors.secondary
                          : (isDark
                              ? AppColors.darkInkSoft
                              : AppColors.inkSoft),
                      size: AppSpacing.iconS,
                    ),
                    onPressed: onToggleFavorite,
                    tooltip: isFavorite
                        ? 'Remove from favorites'
                        : 'Add to favorites',
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ),
              ],
            ],
          ),
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space5,
            vertical: AppSpacing.space1,
          ),
        ),
      ),
    );
  }
}

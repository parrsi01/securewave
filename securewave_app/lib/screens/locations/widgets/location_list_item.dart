import 'package:flutter/material.dart';

import '../../../core/models/server_region.dart';
import '../../../ui/design/app_animations.dart';
import '../../../ui/design/app_colors.dart';
import '../../../ui/design/app_spacing.dart';

/// A single row in the locations list representing one VPN server region.
class LocationListItem extends StatelessWidget {
  const LocationListItem({
    super.key,
    required this.server,
    required this.isSelected,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final ServerRegion server;
  final bool isSelected;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  /// Derive a flag emoji from a country name. Falls back to a globe icon
  /// character when the country is unknown or cannot be mapped.
  static String _flagForCountry(String? country) {
    if (country == null || country.isEmpty) return '\u{1F310}'; // globe
    final code = _countryToCode(country);
    if (code == null) return '\u{1F310}';
    // Regional indicator symbols: 0x1F1E6 is 'A'
    final first = 0x1F1E6 + (code.codeUnitAt(0) - 0x41);
    final second = 0x1F1E6 + (code.codeUnitAt(1) - 0x41);
    return String.fromCharCodes([first, second]);
  }

  static String? _countryToCode(String country) {
    const map = {
      'united states': 'US',
      'united kingdom': 'GB',
      'germany': 'DE',
      'france': 'FR',
      'japan': 'JP',
      'singapore': 'SG',
      'australia': 'AU',
      'canada': 'CA',
      'netherlands': 'NL',
      'sweden': 'SE',
      'switzerland': 'CH',
      'brazil': 'BR',
      'india': 'IN',
      'south korea': 'KR',
      'ireland': 'IE',
      'italy': 'IT',
      'spain': 'ES',
      'poland': 'PL',
      'norway': 'NO',
      'finland': 'FI',
      'denmark': 'DK',
      'austria': 'AT',
      'belgium': 'BE',
      'czech republic': 'CZ',
      'portugal': 'PT',
      'romania': 'RO',
      'south africa': 'ZA',
      'mexico': 'MX',
      'argentina': 'AR',
      'chile': 'CL',
      'new zealand': 'NZ',
      'hong kong': 'HK',
      'taiwan': 'TW',
      'israel': 'IL',
      'turkey': 'TR',
      'ukraine': 'UA',
    };
    // If the country string is already a two-letter code, use it directly.
    if (country.length == 2) return country.toUpperCase();
    return map[country.toLowerCase()];
  }

  Color _latencyColor(int? ms) {
    if (ms == null) return AppColors.inkSoft;
    if (ms < 50) return AppColors.success;
    if (ms < 100) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flag = _flagForCountry(server.country);
    final latencyMs = server.latencyMs;
    final latencyText = latencyMs != null ? '${latencyMs}ms' : '--';

    return AnimatedContainer(
      duration: AppAnimations.durationFast,
      curve: AppAnimations.curveDefault,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.border,
          width: isSelected ? 1.5 : 1,
        ),
        color: isSelected
            ? AppColors.primaryLight.withValues(alpha: 0.3)
            : AppColors.surface,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space4,
              vertical: AppSpacing.space3,
            ),
            child: Row(
              children: [
                // Flag / globe
                Text(flag, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: AppSpacing.space3),

                // City + country
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (server.country != null &&
                          server.country!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          server.country!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.inkMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                // Latency badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space2,
                    vertical: AppSpacing.space1,
                  ),
                  decoration: BoxDecoration(
                    color: _latencyColor(latencyMs).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: Text(
                    latencyText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _latencyColor(latencyMs),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.space2),

                // Favorite star
                GestureDetector(
                  onTap: onToggleFavorite,
                  child: AnimatedSwitcher(
                    duration: AppAnimations.favoriteToggle,
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(scale: animation, child: child);
                    },
                    child: Icon(
                      isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                      key: ValueKey(isFavorite),
                      color: isFavorite ? AppColors.secondary : AppColors.inkSoft,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.space1),

                // Selected checkmark
                AnimatedOpacity(
                  opacity: isSelected ? 1.0 : 0.0,
                  duration: AppAnimations.checkmarkFade,
                  child: const Icon(
                    Icons.check_circle,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

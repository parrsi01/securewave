import 'package:flutter/material.dart';

import '../../../core/models/server_region.dart';
import '../../../ui/design/app_animations.dart';
import '../../../ui/design/app_colors.dart';
import '../../../ui/design/app_spacing.dart';

String countryFlag(String? country) {
  const map = {
    'United States': '\u{1f1fa}\u{1f1f8}', 'Germany': '\u{1f1e9}\u{1f1ea}',
    'Netherlands': '\u{1f1f3}\u{1f1f1}', 'United Kingdom': '\u{1f1ec}\u{1f1e7}',
    'France': '\u{1f1eb}\u{1f1f7}', 'Japan': '\u{1f1ef}\u{1f1f5}',
    'Singapore': '\u{1f1f8}\u{1f1ec}', 'Australia': '\u{1f1e6}\u{1f1fa}',
    'Canada': '\u{1f1e8}\u{1f1e6}', 'Sweden': '\u{1f1f8}\u{1f1ea}',
    'Switzerland': '\u{1f1e8}\u{1f1ed}', 'Brazil': '\u{1f1e7}\u{1f1f7}',
    'India': '\u{1f1ee}\u{1f1f3}', 'South Korea': '\u{1f1f0}\u{1f1f7}',
    'Ireland': '\u{1f1ee}\u{1f1ea}', 'Italy': '\u{1f1ee}\u{1f1f9}',
    'Spain': '\u{1f1ea}\u{1f1f8}', 'Poland': '\u{1f1f5}\u{1f1f1}',
    'Norway': '\u{1f1f3}\u{1f1f4}', 'Finland': '\u{1f1eb}\u{1f1ee}',
    'Denmark': '\u{1f1e9}\u{1f1f0}', 'Austria': '\u{1f1e6}\u{1f1f9}',
    'Belgium': '\u{1f1e7}\u{1f1ea}', 'Czech Republic': '\u{1f1e8}\u{1f1ff}',
    'Portugal': '\u{1f1f5}\u{1f1f9}', 'Romania': '\u{1f1f7}\u{1f1f4}',
    'South Africa': '\u{1f1ff}\u{1f1e6}', 'Mexico': '\u{1f1f2}\u{1f1fd}',
    'Argentina': '\u{1f1e6}\u{1f1f7}', 'Chile': '\u{1f1e8}\u{1f1f1}',
    'New Zealand': '\u{1f1f3}\u{1f1ff}', 'Hong Kong': '\u{1f1ed}\u{1f1f0}',
    'Taiwan': '\u{1f1f9}\u{1f1fc}', 'Israel': '\u{1f1ee}\u{1f1f1}',
    'Turkey': '\u{1f1f9}\u{1f1f7}', 'Ukraine': '\u{1f1fa}\u{1f1e6}',
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

class ServerTile extends StatelessWidget {
  const ServerTile({
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

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Server: ${server.name}, ${server.city ?? server.country ?? ""}. ${server.latencyMs != null ? "Latency: ${server.latencyMs}ms." : ""}',
      child: AnimatedContainer(
        duration: AppAnimations.durationFast,
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: isSelected ? 2 : 1,
          ),
          color: isSelected ? AppColors.primaryLight.withValues(alpha: 0.3) : null,
        ),
        child: ListTile(
          leading: Text(countryFlag(server.country), style: const TextStyle(fontSize: 24)),
          title: Text(server.name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
          subtitle: Text(
            [server.city, server.country].where((s) => s != null).join(', '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkMuted),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (server.latencyMs != null) ...[
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: AppColors.border,
                  ),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (server.latencyMs!.clamp(0, 200) / 200).toDouble(),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: _latencyColor(server.latencyMs),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${server.latencyMs}ms',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _latencyColor(server.latencyMs),
                        fontSize: 11,
                      ),
                ),
                const SizedBox(width: AppSpacing.space2),
              ],
              IconButton(
                icon: Icon(
                  isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: isFavorite ? AppColors.secondary : AppColors.inkSoft,
                  size: 20,
                ),
                onPressed: onToggleFavorite,
                tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
              ),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/models/server_region.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/widgets/ui_helpers.dart';

/// Compact server tile for use in lists (server selection screen).
class ServerTile extends StatelessWidget {
  const ServerTile({
    super.key,
    required this.server,
    required this.isSelected,
    required this.onTap,
    this.isFavorite = false,
    this.enabled = true,
    this.disabledReason,
    this.onToggleFavorite,
  });

  final ServerRegion server;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isFavorite;
  final bool enabled;
  final String? disabledReason;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final flag = flagEmoji(server.countryCode);
    final isPremium =
        server.premiumOnly || server.tierRestriction == 'premium';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Text(
            flag.isNotEmpty ? flag : '🌐',
            style: const TextStyle(fontSize: 22),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  server.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: enabled ? null : AppColors.inkSoft,
                      ),
                ),
              ),
              if (isPremium)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryDark,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: const Text(
                    'Premium',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: server.city != null ? Text(server.city!) : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onToggleFavorite != null)
                IconButton(
                  icon: Icon(
                    isFavorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: isFavorite
                        ? AppColors.secondary
                        : AppColors.inkSoft,
                    size: AppSpacing.iconS,
                  ),
                  onPressed: onToggleFavorite,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              if (isSelected)
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.primary)
              else
                Text(
                  latencyLabel(server.latencyMs),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.inkSoft,
                      ),
                ),
            ],
          ),
          selected: isSelected,
          selectedTileColor: AppColors.primaryGhost,
          enabled: enabled,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          ),
          onTap: enabled ? onTap : null,
        ),
        if (disabledReason != null && !enabled)
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.space7,
              bottom: AppSpacing.space2,
            ),
            child: Text(
              disabledReason!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.warning,
                  ),
            ),
          ),
      ],
    );
  }
}

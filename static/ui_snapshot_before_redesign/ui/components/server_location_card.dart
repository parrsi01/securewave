import 'package:flutter/material.dart';

import '../../core/models/server_region.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/widgets/ui_helpers.dart';

/// Compact pill showing the selected server's location.
class ServerLocationCard extends StatelessWidget {
  const ServerLocationCard({
    super.key,
    required this.server,
    this.onTap,
  });

  final ServerRegion server;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final flag = flagEmoji(server.countryCode);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppSpacing.radiusM),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space4,
            vertical: AppSpacing.space3,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                flag.isNotEmpty ? flag : '🌐',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(width: AppSpacing.space2),
              Flexible(
                child: Text(
                  server.name,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: AppSpacing.space1),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: AppSpacing.iconXS,
                  color: AppColors.primaryBright,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

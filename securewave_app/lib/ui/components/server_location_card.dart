import 'package:flutter/material.dart';

import '../../core/models/server_region.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/widgets/ui_helpers.dart';

/// Card showing a server region's location — used in the server pill on the
/// home screen.
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusM),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space2,
        ),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              flag.isNotEmpty ? flag : '🌐',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(width: AppSpacing.space2),
            Text(
              server.name,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.primaryDeep,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: AppSpacing.space1),
              const Icon(
                Icons.chevron_right_rounded,
                size: AppSpacing.iconXS,
                color: AppColors.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

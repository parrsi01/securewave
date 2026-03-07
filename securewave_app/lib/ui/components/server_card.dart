import 'package:flutter/material.dart';

import '../../core/models/server_region.dart';
import '../design/app_colors.dart';
import '../design/app_spacing.dart';
import '../widgets/ui_helpers.dart';

/// Card widget for a single server region.
class ServerCard extends StatelessWidget {
  const ServerCard({
    super.key,
    required this.server,
    required this.isSelected,
    required this.onTap,
    this.trailing,
  });

  final ServerRegion server;
  final bool isSelected;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final flag = flagEmoji(server.countryCode);
    final borderColor =
        isSelected ? AppColors.primary : Colors.transparent;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        side: BorderSide(color: borderColor, width: 2),
      ),
      child: ListTile(
        leading: Text(
          flag.isNotEmpty ? flag : '🌐',
          style: const TextStyle(fontSize: 24),
        ),
        title: Text(
          server.name,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: server.city != null
            ? Text(
                server.city!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.inkSoft,
                    ),
              )
            : null,
        trailing: trailing ??
            (isSelected
                ? const Icon(Icons.check_circle_rounded,
                    color: AppColors.primary)
                : null),
        onTap: onTap,
      ),
    );
  }
}

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isSelected
        ? AppColors.primaryBright
        : (isDark ? AppColors.darkBorder : Colors.transparent);
    final bgColor = isDark ? AppColors.darkSurface : null;

    return Card(
      margin: EdgeInsets.zero,
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        side: BorderSide(color: borderColor, width: isSelected ? 2 : 1),
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
                      color: AppColors.darkInkSoft,
                    ),
              )
            : null,
        trailing: trailing ??
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (server.latencyMs != null) ...[
                  _LatencyPill(latencyMs: server.latencyMs!),
                  const SizedBox(width: AppSpacing.space2),
                ],
                if (isSelected)
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.primaryBright),
              ],
            ),
        onTap: onTap,
      ),
    );
  }
}

class _LatencyPill extends StatelessWidget {
  const _LatencyPill({required this.latencyMs});
  final int latencyMs;

  @override
  Widget build(BuildContext context) {
    final color = _latencyColor(latencyMs);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        '$latencyMs ms',
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _latencyColor(int ms) {
    if (ms <= 40) return AppColors.success;
    if (ms <= 100) return AppColors.warning;
    return AppColors.error;
  }
}

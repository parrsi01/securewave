import 'package:flutter/material.dart';

import '../core/models/server_region.dart';
import 'app_ui_v1.dart';
import 'components/depth_panel.dart';

class ServerCard extends StatelessWidget {
  const ServerCard({
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
    final subtitle = [
      if (server.country?.isNotEmpty ?? false) server.country!,
      if (server.latencyMs != null) '${server.latencyMs} ms',
    ].join('  ');

    return DepthPanel(
      depth: isSelected ? PanelDepth.floating : PanelDepth.raised,
      isAccent: isSelected,
      onTap: onTap,
      padding: const EdgeInsets.all(AppUIv1.space4),
      borderRadius: BorderRadius.circular(28),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? AppUIv1.accentSoft : AppUIv1.panelBase,
              border: Border.all(
                color: isSelected
                    ? AppUIv1.accent.withValues(alpha: 0.28)
                    : AppUIv1.borderStrong,
              ),
            ),
            child: Icon(
              Icons.public,
              color: isSelected ? AppUIv1.accent : AppUIv1.inkSoft,
            ),
          ),
          const SizedBox(width: AppUIv1.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(server.name,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppUIv1.space1),
                Text(
                  subtitle.isEmpty ? 'Region available' : subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onToggleFavorite,
            icon: Icon(
                isFavorite ? Icons.star_rounded : Icons.star_border_rounded),
            color: isFavorite ? AppUIv1.accent : AppUIv1.inkSoft,
          ),
          const SizedBox(width: AppUIv1.space1),
          Icon(
            isSelected ? Icons.check_circle : Icons.chevron_right,
            color: isSelected ? AppUIv1.accent : AppUIv1.inkSoft,
          ),
        ],
      ),
    );
  }
}

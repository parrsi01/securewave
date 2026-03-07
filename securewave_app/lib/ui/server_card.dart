import 'package:flutter/material.dart';

import '../core/models/server_region.dart';
import 'app_ui_v1.dart';

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

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppUIv1.space4),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? AppUIv1.accentSoft : AppUIv1.surfaceMuted,
                ),
                child: Icon(
                  Icons.public,
                  color: isSelected ? AppUIv1.accentStrong : AppUIv1.inkSoft,
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
                icon: Icon(isFavorite
                    ? Icons.star_rounded
                    : Icons.star_border_rounded),
                color: isFavorite ? AppUIv1.accentSun : AppUIv1.inkSoft,
              ),
              const SizedBox(width: AppUIv1.space1),
              Icon(
                isSelected ? Icons.check_circle : Icons.chevron_right,
                color: isSelected ? AppUIv1.accentStrong : AppUIv1.inkSoft,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

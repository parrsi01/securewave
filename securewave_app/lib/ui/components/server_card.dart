import 'package:flutter/material.dart';

import '../../core/models/server_region.dart';
import '../../debug/automation_keys.dart';
import '../theme/securewave_palette.dart';
import '../theme/securewave_theme.dart';
import '../widgets/ui_helpers.dart';

class ServerCard extends StatelessWidget {
  const ServerCard({
    super.key,
    required this.server,
    required this.isSelected,
    required this.isFavorite,
    required this.enabled,
    required this.onTap,
    required this.onToggleFavorite,
    this.disabledReason,
  });

  final ServerRegion server;
  final bool isSelected;
  final bool isFavorite;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final load = estimateServerLoad(server);
    final loadColor = load >= 80
        ? context.swColors.connectionError
        : (load >= 55
            ? SecureWavePalette.warning
            : context.swColors.connectionActive);
    final health =
        (server.regionHealthStatus ?? server.healthStatus ?? 'unknown')
            .trim()
            .toLowerCase();
    final statusColor = switch (health) {
      'up' => SecureWavePalette.success,
      'down' => SecureWavePalette.danger,
      _ => SecureWavePalette.warning,
    };

    return Opacity(
      opacity: enabled ? 1 : 0.7,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: SecureWaveSpacing.spaceXS),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SecureWaveRadius.lg),
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.35),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey<String>(AutomationKeys.serverTile(server.id)),
            borderRadius: BorderRadius.circular(SecureWaveRadius.lg),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(SecureWaveSpacing.spaceSM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        flagEmoji(server.countryCode),
                        style: const TextStyle(fontSize: 26),
                      ),
                      const SizedBox(width: SecureWaveSpacing.spaceXS),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              server.country ?? server.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                if ((server.city ?? '').trim().isNotEmpty)
                                  server.city!.trim(),
                                server.id,
                              ].join(' • '),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onToggleFavorite,
                        icon: Icon(
                          isFavorite
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: isFavorite
                              ? SecureWavePalette.warning
                              : Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: SecureWaveSpacing.spaceSM),
                  Wrap(
                    spacing: SecureWaveSpacing.spaceXS,
                    runSpacing: SecureWaveSpacing.spaceXS,
                    children: <Widget>[
                      _MetaPill(
                        label: latencyLabel(server.latencyMs),
                        icon: Icons.speed_rounded,
                      ),
                      _MetaPill(
                        label: 'Load $load%',
                        icon: Icons.stacked_bar_chart_rounded,
                        tint: loadColor,
                      ),
                      _MetaPill(
                        label: health.toUpperCase(),
                        icon: Icons.fiber_manual_record_rounded,
                        tint: statusColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: SecureWaveSpacing.spaceSM),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: load / 100,
                      minHeight: 8,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.7),
                      color: loadColor,
                    ),
                  ),
                  if (!enabled && disabledReason != null) ...<Widget>[
                    const SizedBox(height: SecureWaveSpacing.spaceXS),
                    Text(
                      disabledReason!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: SecureWavePalette.warning,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.label,
    required this.icon,
    this.tint,
  });

  final String label;
  final IconData icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SecureWaveSpacing.spaceXS,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SecureWaveRadius.md),
        color: color.withValues(alpha: 0.08),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}

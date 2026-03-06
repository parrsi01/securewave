import 'package:flutter/material.dart';

import '../../core/models/server_region.dart';
import '../../debug/automation_keys.dart';
import '../theme/securewave_palette.dart';

class ServerTile extends StatelessWidget {
  const ServerTile({
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
    final premium = server.premiumOnly ||
        (server.tierRestriction ?? '').trim().toLowerCase() == 'premium';
    final latency = server.latencyMs == null ? '--' : '${server.latencyMs} ms';
    final health =
        (server.regionHealthStatus ?? server.healthStatus ?? 'unknown')
            .trim()
            .toLowerCase();
    final healthColor = switch (health) {
      'up' => SecureWavePalette.success,
      'down' => SecureWavePalette.danger,
      _ => SecureWavePalette.warning,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.7),
        ),
        color: Theme.of(context)
            .colorScheme
            .surface
            .withValues(alpha: enabled ? 1 : 0.8),
      ),
      child: ListTile(
        key: ValueKey<String>(AutomationKeys.serverTile(server.id)),
        enabled: enabled,
        onTap: enabled ? onTap : null,
        leading: CircleAvatar(
          backgroundColor: healthColor.withValues(alpha: 0.14),
          foregroundColor: healthColor,
          child: Text(
            (server.countryCode ?? server.country ?? server.name)
                .trim()
                .substring(0, 1)
                .toUpperCase(),
          ),
        ),
        title: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                server.country ?? server.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (premium)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: SecureWavePalette.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text('Premium'),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                [
                  if ((server.city ?? '').trim().isNotEmpty)
                    server.city!.trim(),
                  latency,
                  'Health ${health.toUpperCase()}',
                ].join('  •  '),
              ),
              if (!enabled && disabledReason != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  disabledReason!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SecureWavePalette.warning,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ],
          ),
        ),
        trailing: IconButton(
          onPressed: onToggleFavorite,
          icon: Icon(
            isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
            color: isFavorite
                ? SecureWavePalette.warning
                : Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

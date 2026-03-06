import 'package:flutter/material.dart';

import '../../core/models/server_region.dart';
import '../design_tokens.dart';
import '../theme/spacing.dart';
import 'dashboard_card.dart';

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
    final latency = server.latencyMs;
    final latencyColor = latency == null
        ? SecureWaveTokens.inkSoft
        : latency < 50
            ? SecureWaveTokens.success
            : latency < 90
                ? SecureWaveTokens.accentSun
                : SecureWaveTokens.warning;

    return InkWell(
      borderRadius: BorderRadius.circular(SecureWaveTokens.radiusLg),
      onTap: onTap,
      child: DashboardCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? SecureWaveTokens.accentSoft
                    : SecureWaveTokens.surfaceMuted,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.public_rounded,
                color: isSelected
                    ? SecureWaveTokens.accentStrong
                    : SecureWaveTokens.inkMuted,
              ),
            ),
            const SizedBox(width: SecureWaveSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          server.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_circle,
                            color: SecureWaveTokens.success),
                    ],
                  ),
                  const SizedBox(height: SecureWaveSpacing.xs),
                  Text(
                    server.country ?? server.city ?? 'SecureWave region',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SecureWaveTokens.inkMuted,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: SecureWaveSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onToggleFavorite,
                  icon: Icon(
                    isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                    color: isFavorite
                        ? SecureWaveTokens.accentSun
                        : SecureWaveTokens.inkSoft,
                  ),
                  label: Text(isFavorite ? 'Saved' : 'Save'),
                ),
                if (latency != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SecureWaveSpacing.sm,
                      vertical: SecureWaveSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: latencyColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$latency ms',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: latencyColor,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

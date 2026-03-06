import 'package:flutter/material.dart';

import '../theme/securewave_theme.dart';
import '../widgets/glass_panel.dart';
import 'protocol_badge.dart';
import 'status_indicator.dart';

class ConnectionCard extends StatelessWidget {
  const ConnectionCard({
    super.key,
    required this.statusLabel,
    required this.statusDetail,
    required this.statusColor,
    required this.statusIcon,
    required this.locationLabel,
    required this.protocolLabel,
    required this.timerLabel,
    required this.addressLabel,
  });

  final String statusLabel;
  final String statusDetail;
  final Color statusColor;
  final IconData statusIcon;
  final String locationLabel;
  final String protocolLabel;
  final String timerLabel;
  final String addressLabel;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              StatusIndicator(
                label: statusLabel,
                detail: statusDetail,
                color: statusColor,
                icon: statusIcon,
                emphasized: true,
              ),
              ProtocolBadge(label: protocolLabel),
            ],
          ),
          const SizedBox(height: SecureWaveSpacing.spaceSM),
          Wrap(
            spacing: SecureWaveSpacing.spaceSM,
            runSpacing: SecureWaveSpacing.spaceSM,
            children: <Widget>[
              _StatBlock(label: 'Current server', value: locationLabel),
              _StatBlock(label: 'Exit IP', value: addressLabel),
              _StatBlock(label: 'Session timer', value: timerLabel),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.all(SecureWaveSpacing.spaceSM),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SecureWaveRadius.lg),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.42),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: SecureWaveSpacing.spaceXS),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

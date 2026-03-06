import 'package:flutter/material.dart';

import '../../core/models/vpn_status.dart';
import '../design_tokens.dart';
import '../theme/spacing.dart';

class StatusIndicator extends StatelessWidget {
  const StatusIndicator({
    super.key,
    required this.status,
    required this.label,
  });

  final VpnStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      VpnStatus.connected => SecureWaveTokens.success,
      VpnStatus.connecting => SecureWaveTokens.accentSun,
      VpnStatus.reconnecting => SecureWaveTokens.accentSun,
      VpnStatus.disconnecting => SecureWaveTokens.warning,
      VpnStatus.error => SecureWaveTokens.danger,
      VpnStatus.disconnected => SecureWaveTokens.inkSoft,
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SecureWaveSpacing.md,
        vertical: SecureWaveSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: SecureWaveSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                ),
          ),
        ],
      ),
    );
  }
}

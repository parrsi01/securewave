import 'package:flutter/material.dart';

import '../core/models/vpn_status.dart';
import 'app_ui_v1.dart';

class StatusIndicator extends StatelessWidget {
  const StatusIndicator({
    super.key,
    required this.status,
    required this.label,
    this.large = false,
  });

  final VpnStatus status;
  final String label;
  final bool large;

  Color get _color {
    switch (status) {
      case VpnStatus.connected:
        return AppUIv1.success;
      case VpnStatus.connecting:
      case VpnStatus.reconnecting:
      case VpnStatus.disconnecting:
        return AppUIv1.accentSun;
      case VpnStatus.error:
        return AppUIv1.danger;
      case VpnStatus.disconnected:
        return AppUIv1.inkSoft;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dotSize = large ? 18.0 : 12.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: dotSize,
          height: dotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _color,
            boxShadow: [
              BoxShadow(
                color: _color.withValues(alpha: 0.35),
                blurRadius: large ? 24 : 12,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppUIv1.space2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

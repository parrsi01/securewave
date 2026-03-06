import 'package:flutter/material.dart';

import '../theme/securewave_palette.dart';
import '../widgets/vpn_ui_bindings.dart';

class StatusIndicator extends StatelessWidget {
  const StatusIndicator({
    super.key,
    required this.label,
    required this.color,
    required this.icon,
    this.detail,
    this.emphasized = false,
  });

  final String label;
  final String? detail;
  final Color color;
  final IconData icon;
  final bool emphasized;

  static Color colorFor(ConnectionVisualState state) {
    return switch (state) {
      ConnectionVisualState.connected => SecureWavePalette.success,
      ConnectionVisualState.connecting ||
      ConnectionVisualState.reconnecting ||
      ConnectionVisualState.disconnecting =>
        SecureWavePalette.warning,
      ConnectionVisualState.error => SecureWavePalette.danger,
      ConnectionVisualState.disconnected => SecureWavePalette.mint,
    };
  }

  static IconData iconFor(ConnectionVisualState state) {
    return switch (state) {
      ConnectionVisualState.connected => Icons.check_circle_rounded,
      ConnectionVisualState.connecting ||
      ConnectionVisualState.reconnecting ||
      ConnectionVisualState.disconnecting =>
        Icons.autorenew_rounded,
      ConnectionVisualState.error => Icons.error_outline_rounded,
      ConnectionVisualState.disconnected => Icons.shield_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: emphasized ? 16 : 12,
        vertical: emphasized ? 12 : 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: emphasized ? 18 : 16, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: color,
                      ),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: color.withValues(alpha: 0.9),
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

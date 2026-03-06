import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../theme/spacing.dart';

class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SecureWaveSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SecureWaveTokens.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(SecureWaveTokens.radiusLg),
        border: Border.all(color: SecureWaveTokens.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 32,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

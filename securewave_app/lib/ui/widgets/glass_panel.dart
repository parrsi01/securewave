import 'package:flutter/material.dart';

import '../layout/layout_tokens.dart';
import '../theme/securewave_theme.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(LayoutTokens.pagePadding),
    this.gradient,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LayoutTokens.cardRadius),
        border: Border.all(
          color: borderColor ??
              Theme.of(context)
                  .colorScheme
                  .outline
                  .withValues(alpha: isDark ? 0.85 : 0.65),
        ),
        gradient: gradient ?? context.swGradients.panel,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color:
                (isDark ? Colors.black : Theme.of(context).colorScheme.shadow)
                    .withValues(alpha: isDark ? 0.14 : 0.05),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

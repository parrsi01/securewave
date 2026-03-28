import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

enum PanelDepth { sunken, base, raised, floating }

class DepthPanelStyle {
  const DepthPanelStyle({
    required this.backgroundColor,
    required this.borderColor,
    required this.shadows,
  });

  final Color backgroundColor;
  final Color borderColor;
  final List<BoxShadow> shadows;
}

class DepthPanel extends StatelessWidget {
  const DepthPanel({
    super.key,
    required this.child,
    this.depth = PanelDepth.base,
    this.padding = const EdgeInsets.all(AppTokens.paddingM),
    this.margin,
    this.borderRadius = AppTokens.brCard,
    this.onTap,
    this.isAccent = false,
  });

  final Widget child;
  final PanelDepth depth;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius borderRadius;
  final VoidCallback? onTap;
  final bool isAccent;

  static DepthPanelStyle styleOf(
    PanelDepth depth, {
    bool isAccent = false,
  }) {
    const accentBorder = HtbColors.borderAccent;
    const accentGlow = BoxShadow(
      color: HtbColors.glowPrimarySoft,
      blurRadius: 18,
      offset: Offset(0, 10),
    );

    return switch (depth) {
      PanelDepth.sunken => DepthPanelStyle(
          backgroundColor: HtbColors.panelSunken,
          borderColor: isAccent ? accentBorder : HtbColors.borderSubtle,
          shadows: const [],
        ),
      PanelDepth.base => DepthPanelStyle(
          backgroundColor: HtbColors.panelBase,
          borderColor: isAccent ? accentBorder : HtbColors.glassBorderDefault,
          shadows: isAccent
              ? [...AppTokens.shadowLow, accentGlow]
              : AppTokens.shadowLow,
        ),
      PanelDepth.raised => DepthPanelStyle(
          backgroundColor: HtbColors.panelRaised,
          borderColor: isAccent ? accentBorder : HtbColors.borderStrong,
          shadows: isAccent
              ? [...AppTokens.shadowMedium, accentGlow]
              : AppTokens.shadowMedium,
        ),
      PanelDepth.floating => DepthPanelStyle(
          backgroundColor: HtbColors.panelFloating,
          borderColor: isAccent ? accentBorder : HtbColors.borderStrong,
          shadows: isAccent
              ? [...AppTokens.shadowHigh, accentGlow]
              : AppTokens.shadowHigh,
        ),
    };
  }

  static Color colorOf(PanelDepth depth) => styleOf(depth).backgroundColor;

  @override
  Widget build(BuildContext context) {
    final style = styleOf(depth, isAccent: isAccent);
    final content =
        padding == null ? child : Padding(padding: padding!, child: child);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: borderRadius,
        border: Border.all(
          color: style.borderColor,
          width: AppTokens.borderWidth,
        ),
        boxShadow: style.shadows,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                borderRadius: borderRadius,
                child: content,
              ),
      ),
    );
  }
}

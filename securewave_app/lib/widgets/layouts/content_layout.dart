import 'package:flutter/material.dart';

class ContentLayout extends StatelessWidget {
  const ContentLayout({
    super.key,
    required this.child,
    this.maxWidth = 1120,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final horizontal = width < 520 ? 16.0 : width < 900 ? 24.0 : 32.0;
        final vertical = width < 520 ? 20.0 : 24.0;
        final resolvedPadding = padding ?? EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
        final available = width - resolvedPadding.horizontal;
        final targetMaxWidth = available < maxWidth ? available : maxWidth;

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: targetMaxWidth),
            child: Padding(
              padding: resolvedPadding,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

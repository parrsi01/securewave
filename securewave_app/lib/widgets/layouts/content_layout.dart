import 'package:flutter/material.dart';

class ContentLayout extends StatelessWidget {
  const ContentLayout({
    super.key,
    required this.child,
    this.maxWidth = 980,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final horizontal = width < 520 ? 16.0 : 24.0;
    final vertical = width < 520 ? 20.0 : 24.0;
    final resolvedPadding = padding ?? EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: resolvedPadding,
          child: child,
        ),
      ),
    );
  }
}

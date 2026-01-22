import 'package:flutter/material.dart';

class ResponsiveWrap extends StatelessWidget {
  const ResponsiveWrap({
    super.key,
    required this.children,
    this.minItemWidth = 220,
    this.maxItemWidth,
    this.spacing = 12,
    this.runSpacing = 12,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double? maxItemWidth;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final targetWidth = maxItemWidth ?? minItemWidth;
        final columns = ((width + spacing) / (targetWidth + spacing)).floor().clamp(1, children.length);
        final itemWidth = (width - (columns - 1) * spacing) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children)
              SizedBox(
                width: itemWidth.clamp(minItemWidth, maxItemWidth ?? itemWidth),
                child: child,
              ),
          ],
        );
      },
    );
  }
}

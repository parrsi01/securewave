import 'package:flutter/material.dart';

import 'layout_tokens.dart';
import '../theme/securewave_theme.dart';
import '../widgets/section_header.dart';

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
    this.maxWidth = LayoutTokens.contentMaxWidth,
  });

  final String? eyebrow;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: context.swGradients.canvas),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(LayoutTokens.pagePadding),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionHeader(
                  eyebrow: eyebrow,
                  title: title,
                  subtitle: subtitle,
                  trailing: trailing,
                ),
                const SizedBox(height: LayoutTokens.sectionGap),
                child,
                const SizedBox(height: LayoutTokens.sectionGap),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

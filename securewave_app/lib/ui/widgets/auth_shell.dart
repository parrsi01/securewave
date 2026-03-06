import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/securewave_theme.dart';
import 'brand_mark.dart';
import 'glass_panel.dart';
import 'securewave_motion_art.dart';

class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.footer,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: context.swGradients.canvas),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: GlassPanel(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const BrandMark(size: 40),
                    const SizedBox(height: 28),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    const SizedBox(
                      height: 120,
                      child: SecureWaveMotionArt(opacity: 0.16),
                    ),
                    const SizedBox(height: 20),
                    child,
                    if (footer != null) ...<Widget>[
                      const SizedBox(height: 18),
                      footer!,
                    ],
                  ],
                ),
              ).animate().fadeIn(duration: 280.ms).slideY(begin: 0.08),
            ),
          ),
        ),
      ),
    );
  }
}

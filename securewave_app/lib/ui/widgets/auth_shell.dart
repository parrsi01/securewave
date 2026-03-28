import 'package:flutter/material.dart';

import '../components/depth_panel.dart';
import '../components/htb_background.dart';
import '../design/app_spacing.dart';
import '../theme/app_colors.dart' as htb;
import 'brand_mark.dart';

/// Auth screen wrapper with shared background and centered panel.
///
/// Provides a consistent layout for login, register, and password reset
/// screens with a reusable raised panel constrained to
/// [AppSpacing.authMaxWidth].
class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.child, this.title = ''});

  final Widget child;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: htb.HtbColors.bg0,
      body: Stack(
        children: [
          // HTB grid + radial glow
          const HtbBackground(),

          Column(
            children: [
              // ── Branding header ────────────────────────────────────────
              Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + AppSpacing.space6,
                  bottom: AppSpacing.space3,
                  left: AppSpacing.pagePadding,
                  right: AppSpacing.pagePadding,
                ),
                child: Column(
                  children: [
                    const BrandMark(size: 48, textSize: 24),
                    const SizedBox(height: AppSpacing.space3),
                    if (title.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.space2),
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: htb.HtbColors.textSecondary,
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),

              // ── Scrollable body ────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pagePadding,
                    vertical: AppSpacing.space4,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppSpacing.authMaxWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DepthPanel(
                            depth: PanelDepth.raised,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusL,
                            ),
                            padding: const EdgeInsets.all(
                              AppSpacing.cardPadding,
                            ),
                            child: child,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

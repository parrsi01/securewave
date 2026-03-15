import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_spacing.dart';

/// Auth screen wrapper with gradient background and centered card.
///
/// Provides a consistent layout for login, register, and password reset
/// screens: a deep navy gradient background, then scrollable centered
/// content constrained to [AppSpacing.authMaxWidth].
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.child,
    this.title = '',
  });

  final Widget child;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppColors.navyGradient : null,
          color: isDark ? null : AppColors.background,
        ),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            if (title.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + AppSpacing.space5,
                  bottom: AppSpacing.space4,
                  left: AppSpacing.pagePadding,
                  right: AppSpacing.pagePadding,
                ),
                child: Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

            // ── Scrollable body ──────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.pagePadding,
                  vertical: AppSpacing.space6,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.authMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Material(
                          color: isDark
                              ? AppColors.darkSurface
                              : theme.colorScheme.surface,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusL),
                          elevation: isDark ? 0 : 1,
                          child: Container(
                            decoration: isDark
                                ? BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusL),
                                    border: Border.all(
                                      color: AppColors.darkBorder,
                                      width: 1,
                                    ),
                                  )
                                : null,
                            padding:
                                const EdgeInsets.all(AppSpacing.cardPadding),
                            child: child,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_spacing.dart';

/// Auth screen wrapper with gradient header and centered content column.
///
/// Provides a consistent layout for login, register, and password reset
/// screens: a teal gradient header band at the top, then scrollable centered
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
      body: Column(
        children: [
          // ── Gradient header ──────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + AppSpacing.space5,
              bottom: AppSpacing.space6,
              left: AppSpacing.pagePadding,
              right: AppSpacing.pagePadding,
            ),
            decoration: const BoxDecoration(
              gradient: AppColors.authHeaderGradient,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(AppSpacing.radiusXXL),
                bottomRight: Radius.circular(AppSpacing.radiusXXL),
              ),
            ),
            child: title.isNotEmpty
                ? Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  )
                : const SizedBox.shrink(),
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
                            : AppColors.surface,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusL),
                        elevation: isDark ? 0 : 1,
                        child: Padding(
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
    );
  }
}

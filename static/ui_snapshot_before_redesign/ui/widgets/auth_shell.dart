import 'package:flutter/material.dart';

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

    return Scaffold(
      body: Column(
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
                        color: theme.colorScheme.surface,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusL),
                        elevation: 1,
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

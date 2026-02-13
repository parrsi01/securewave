import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/auth_session.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';

/// Phase 4 rebuild of the account screen.
///
/// Shows user identity, current plan summary with data usage,
/// an upgrade CTA, and sign-out.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    final theme = Theme.of(context);

    // Demo fallback for email display
    const demoEmail = 'demo@securewave.app';

    // Hardcoded plan data for the initial build
    const planName = 'Free Plan';
    const usedGb = 2.1;
    const capGb = 5.0;
    final usagePercent = (usedGb / capGb).clamp(0.0, 1.0);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.space5),
            children: [
              const SizedBox(height: AppSpacing.space4),

              // -- Avatar
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryLight,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    size: 44,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space4),

              // -- Email
              Center(
                child: Text(
                  auth.isAuthenticated ? demoEmail : 'Not signed in',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space6),

              // -- Plan card
              Container(
                padding: const EdgeInsets.all(AppSpacing.space5),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusL),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Current plan',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.inkMuted,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.space3,
                            vertical: AppSpacing.space1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceMuted,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusFull),
                          ),
                          child: Text(
                            'Free',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.inkMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.space2),
                    Text(
                      planName,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.space5),

                    // Data usage
                    Text(
                      'Data usage',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.space2),
                    Text(
                      '${usedGb.toStringAsFixed(1)} GB of ${capGb.toStringAsFixed(0)} GB used',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.inkMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space3),
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusFull),
                      child: LinearProgressIndicator(
                        value: usagePercent,
                        minHeight: 8,
                        backgroundColor: AppColors.surfaceMuted,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space2),
                    Text(
                      '${(capGb - usedGb).toStringAsFixed(1)} GB remaining',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space4),

              // -- Upgrade button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Coming soon'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text('Upgrade to Premium'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.space4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusM),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space5),

              // -- Divider
              const Divider(color: AppColors.border),
              const SizedBox(height: AppSpacing.space5),

              // -- Sign Out button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(authSessionProvider).clearSession();
                    if (context.mounted) {
                      context.go('/login');
                    }
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign Out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.space4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusM),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space6),

              // -- App version
              Center(
                child: Text(
                  'SecureWave v1.0.0',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space5),
            ],
          ),
        ),
      ),
    );
  }
}

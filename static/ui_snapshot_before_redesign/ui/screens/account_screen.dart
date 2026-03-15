import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/auth_session.dart';
import '../../core/state/app_state.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/widgets/glass_panel.dart';

/// Account / profile screen.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authSession = ref.watch(authSessionProvider);
    final planAsync = ref.watch(userPlanProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
        centerTitle: false,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Profile card ──────────────────────────────────────────
            GlassPanel(
              child: Column(
                children: [
                  // Avatar
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      gradient: AppColors.brandGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _initials(authSession.email),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space3),
                  Text(
                    authSession.email ?? 'User',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.space2),
                  planAsync.when(
                    loading: () => const SizedBox(
                      width: 80,
                      height: 4,
                      child: LinearProgressIndicator(),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (plan) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.space3,
                          vertical: AppSpacing.space1),
                      decoration: BoxDecoration(
                        gradient: plan.isPremium
                            ? AppColors.brandGradient
                            : null,
                        color: plan.isPremium
                            ? null
                            : AppColors.primaryBright.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusFull),
                      ),
                      child: Text(
                        plan.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: plan.isPremium
                              ? Colors.white
                              : AppColors.primaryBright,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space5),

            // ── Plan usage ────────────────────────────────────────────
            planAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (plan) => !plan.isPremium && plan.dataCapGb > 0
                  ? GlassPanel(
                      padding: const EdgeInsets.all(AppSpacing.space4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Data used',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                        color: AppColors.inkMuted),
                              ),
                              Text(
                                '${plan.usedGb.toStringAsFixed(1)} / ${plan.dataCapGb.toStringAsFixed(0)} GB',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                        fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.space2),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                                AppSpacing.radiusFull),
                            child: LinearProgressIndicator(
                              value: plan.usagePercent,
                              minHeight: 6,
                              backgroundColor: Theme.of(context).colorScheme.outlineVariant,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                plan.usagePercent > 0.8
                                    ? AppColors.error
                                    : AppColors.primaryBright,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            if (planAsync.hasValue &&
                !planAsync.value!.isPremium &&
                planAsync.value!.dataCapGb > 0)
              const SizedBox(height: AppSpacing.space5),

            // ── Actions ───────────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusL),
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  children: [
                    _ActionTile(
                      icon: Icons.edit_outlined,
                      label: 'Edit Profile',
                      onTap: () => context.push('/edit-profile'),
                    ),
                    _divider(context),
                    _ActionTile(
                      icon: Icons.devices_rounded,
                      label: 'Manage Devices',
                      onTap: () => context.push('/devices'),
                    ),
                    _divider(context),
                    _ActionTile(
                      icon: Icons.logout_rounded,
                      label: 'Sign Out',
                      danger: true,
                      onTap: () => _confirmSignOut(context, ref),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
        ),
        ),
    );
  }

  String _initials(String? email) {
    if (email == null || email.isEmpty) return '?';
    return email[0].toUpperCase();
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sign Out',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      ref.read(authSessionProvider).clearSession();
    }
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.primaryBright;
    return ListTile(
      leading: Icon(icon, color: color, size: AppSpacing.iconM),
      title: Text(
        label,
        style: TextStyle(
          color: danger ? AppColors.error : null,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: danger
          ? null
          : const Icon(Icons.chevron_right_rounded,
              size: AppSpacing.iconS, color: AppColors.inkSoft),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space1,
      ),
      onTap: onTap,
    );
  }
}

Widget _divider(BuildContext context) => Divider(
      height: 1,
      indent: AppSpacing.space7,
      color: Theme.of(context).colorScheme.outlineVariant,
    );

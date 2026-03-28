import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/auth_session.dart';
import '../../core/state/app_state.dart';
import '../../debug/automation_keys.dart';
import '../../ui/components/htb_background.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/theme/app_colors.dart' as htb;
import '../../ui/theme/app_tokens.dart';
import '../../ui/widgets/glass_panel.dart';

/// Account / profile screen.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authSession = ref.watch(authSessionProvider);
    final planAsync = ref.watch(userPlanProvider);
    return Scaffold(
      key: AutomationKeys.accountScreenKey,
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: const Text('Account'),
        centerTitle: false,
      ),
      body: HtbScaffoldBackground(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GlassPanel(
                    glowColor: htb.HtbColors.accentPrimaryMuted,
                    borderColor: htb.HtbColors.accentPrimaryGhost,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        htb.HtbColors.accentPrimaryGhost,
                        htb.HtbColors.bg1.withValues(alpha: 0.92),
                        htb.HtbColors.bg3.withValues(alpha: 0.96),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.space3,
                            vertical: AppSpacing.space2,
                          ),
                          decoration: BoxDecoration(
                            color: htb.HtbColors.accentPrimaryGhost,
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusFull),
                            border: Border.all(
                              color: htb.HtbColors.accentPrimaryGhost,
                            ),
                          ),
                          child: Text(
                            'IDENTITY NODE',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: htb.HtbColors.textMono,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.9,
                                ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.space3),
                        Text(
                          'Profile & plan',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.space2),
                        Text(
                          'Manage your SecureWave identity, devices, and subscription status from one place.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: htb.HtbColors.textSecondary,
                                  ),
                        ),
                        const SizedBox(height: AppSpacing.space5),
                        Row(
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: const BoxDecoration(
                                gradient: AppColors.brandGradient,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  _initials(authSession.email),
                                  style: const TextStyle(
                                    color: AppColors.darkBackground,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 24,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.space4),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    authSession.email ?? 'User',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: AppSpacing.space1),
                                  Text(
                                    'SecureWave ID',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: htb.HtbColors.textSecondary,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.space4),
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
                              vertical: AppSpacing.space1,
                            ),
                            decoration: BoxDecoration(
                              gradient: plan.isPremium
                                  ? AppColors.brandGradient
                                  : null,
                              color: plan.isPremium
                                  ? null
                                  : AppColors.primaryBright
                                      .withValues(alpha: AppTokens.opacitySoft),
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
                                    ? AppColors.darkBackground
                                    : AppColors.primaryBright,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space5),
                  GlassPanel(
                    glowColor: htb.HtbColors.accentPrimary,
                    padding: EdgeInsets.zero,
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
                          automationKey: AutomationKeys.accountSignOutButtonKey,
                          icon: Icons.logout_rounded,
                          label: 'Sign Out',

                          danger: true,
                          onTap: () => _confirmSignOut(context, ref),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space5),
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
                                            color: AppColors.inkMuted,
                                          ),
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
                                    AppSpacing.radiusFull,
                                  ),
                                  child: LinearProgressIndicator(
                                    value: plan.usagePercent,
                                    minHeight: 6,
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
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
                    const SizedBox(height: AppSpacing.space1),
                ],
              ),
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
            key: AutomationKeys.accountConfirmSignOutButtonKey,
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
    this.automationKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final Key? automationKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.primaryBright;
    return ListTile(
      key: automationKey,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: AppTokens.opacitySoft),
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          border: Border.all(color: color.withValues(alpha: AppTokens.opacityStrong)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: AppTokens.opacitySoft),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(icon, color: color, size: AppSpacing.iconS),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: danger ? AppColors.error : null,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: danger
          ? null
          : const Icon(
              Icons.chevron_right_rounded,
              size: AppSpacing.iconS,
              color: AppColors.inkSoft,
            ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space1,
      ),
      onTap: onTap,
    );
  }
}

Widget _divider(BuildContext context) => const Divider(
      height: 1,
      indent: AppSpacing.space7,
      color: AppColors.border,
    );

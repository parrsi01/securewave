import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/auth_session.dart';
import '../../core/state/app_state.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/widgets/brand_mark.dart';

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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Profile header ────────────────────────────────────────
            Center(
              child: Column(
                children: [
                  const BrandMark(size: 56),
                  const SizedBox(height: AppSpacing.space4),
                  Text(
                    authSession.email ?? 'User',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  planAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (plan) => Chip(
                      label: Text(
                        plan.name.toUpperCase(),
                        style: const TextStyle(fontSize: 11),
                      ),
                      backgroundColor: AppColors.primaryLight,
                      side: BorderSide.none,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space6),

            // ── Actions ───────────────────────────────────────────────
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.edit_outlined,
                      color: AppColors.primary,
                    ),
                    title: const Text('Edit Profile'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/edit-profile'),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.devices_rounded,
                      color: AppColors.primary,
                    ),
                    title: const Text('Manage Devices'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/devices'),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.logout_rounded,
                      color: AppColors.error,
                    ),
                    title: const Text(
                      'Sign Out',
                      style: TextStyle(color: AppColors.error),
                    ),
                    onTap: () => _confirmSignOut(context, ref),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

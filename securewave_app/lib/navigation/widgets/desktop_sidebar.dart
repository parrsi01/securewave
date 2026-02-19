import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/auth_session.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../nav_destinations.dart';
import 'status_indicator.dart';

class DesktopSidebar extends ConsumerWidget {
  const DesktopSidebar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    final email = auth.email ?? 'Not signed in';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.03),
        border: Border(
          right: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Logo + brand
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.space4, AppSpacing.space5, AppSpacing.space4, AppSpacing.space3,
            ),
            child: Row(
              children: [
                SvgPicture.asset('assets/securewave_logo.svg', width: 28, height: 28),
                const SizedBox(width: AppSpacing.space3),
                Text(
                  'SecureWave',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                ),
              ],
            ),
          ),

          // Status indicator
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space4,
              vertical: AppSpacing.space2,
            ),
            child: const StatusIndicator(showLabel: true),
          ),

          const Divider(height: 1),
          const SizedBox(height: AppSpacing.space2),

          // Navigation items
          ...List.generate(NavDestinations.all.length, (i) {
            final dest = NavDestinations.all[i];
            final selected = i == currentIndex;
            return _NavItem(
              icon: selected ? dest.selectedIcon : dest.icon,
              label: dest.label,
              selected: selected,
              onTap: () => onDestinationSelected(i),
            );
          }),

          const Spacer(),
          const Divider(height: 1),

          // User info
          Padding(
            padding: const EdgeInsets.all(AppSpacing.space4),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.primaryLight,
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.space3),
                Expanded(
                  child: Text(
                    email,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.inkMuted,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  tooltip: 'Sign out',
                  onPressed: () {
                    ref.read(authSessionProvider).clearSession();
                    context.go('/login');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: 2,
      ),
      child: Material(
        color: selected ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space4,
              vertical: AppSpacing.space3,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? AppColors.primary : AppColors.inkMuted,
                ),
                const SizedBox(width: AppSpacing.space3),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: selected ? AppColors.primary : AppColors.ink,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/auth_session.dart';
import '../../debug/automation_keys.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../nav_destinations.dart';
import 'status_indicator.dart';

/// Desktop sidebar — v2.
///
/// 240dp sidebar with:
/// - Logo + brand name header
/// - Live VPN status pill
/// - Navigation items with animated active indicator
/// - User avatar + email + sign-out action
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final email = ref.watch(
      authSessionProvider.select((a) => a.email ?? 'Not signed in'),
    );
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';

    final bgColor =
        isDark ? AppColors.darkBackgroundWarm : AppColors.backgroundWarm;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.border;

    return Container(
      width: AppSpacing.sidebarWidth,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(right: BorderSide(color: borderColor, width: 0.5)),
      ),
      child: Column(
        children: [
          // ── Logo + brand ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.space4,
              AppSpacing.space5,
              AppSpacing.space4,
              AppSpacing.space3,
            ),
            child: Row(
              children: [
                SvgPicture.asset(
                  'assets/securewave_logo.svg',
                  width: 26,
                  height: 26,
                ),
                const SizedBox(width: AppSpacing.space3),
                Text(
                  'SecureWave',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                ),
              ],
            ),
          ),

          // ── Status pill ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space4,
              vertical: AppSpacing.space2,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space3,
                vertical: AppSpacing.space2,
              ),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                border: Border.all(color: borderColor, width: 0.5),
              ),
              child: const StatusIndicator(showLabel: true),
            ),
          ),

          Divider(
              height: AppSpacing.space4,
              thickness: 0.5,
              color: borderColor,
              indent: AppSpacing.space4,
              endIndent: AppSpacing.space4),

          // ── Navigation items ─────────────────────────────────────────
          ...List.generate(NavDestinations.all.length, (i) {
            final dest = NavDestinations.all[i];
            final selected = i == currentIndex;
            return _NavItem(
              automationKey: AutomationKeys.navDestination(dest.label),
              icon: selected ? dest.selectedIcon : dest.icon,
              label: dest.label,
              selected: selected,
              isDark: isDark,
              onTap: () => onDestinationSelected(i),
            );
          }),

          const Spacer(),
          Divider(height: 1, thickness: 0.5, color: borderColor),

          // ── User row ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(AppSpacing.space4),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor:
                      isDark ? AppColors.primaryDeep : AppColors.primaryLight,
                  child: Text(
                    initial,
                    style: TextStyle(
                      color:
                          isDark ? AppColors.primaryBright : AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.space3),
                Expanded(
                  child: Text(
                    email,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.logout_rounded,
                    size: AppSpacing.iconS,
                    color: isDark ? AppColors.darkInkSoft : AppColors.inkSoft,
                  ),
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

// ── Navigation item ────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.automationKey,
    required this.icon,
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final String automationKey;
  final IconData icon;
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primaryColor = isDark ? AppColors.primaryBright : AppColors.primary;
    final activeColor = isDark
        ? AppColors.primaryBright.withValues(alpha: 0.14)
        : AppColors.primaryLight;
    final inkColor = isDark ? AppColors.darkInk : AppColors.ink;
    final mutedColor = isDark ? AppColors.darkInkMuted : AppColors.inkMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: 2,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
          child: InkWell(
            key: ValueKey<String>(automationKey),
            borderRadius: BorderRadius.circular(AppSpacing.radiusL),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space4,
                vertical: AppSpacing.space3,
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      icon,
                      size: AppSpacing.iconM,
                      color: selected ? primaryColor : mutedColor,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: selected ? primaryColor : inkColor,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w400,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../ui/design/app_colors.dart';
import '../ui/design/app_spacing.dart';
import 'nav_destinations.dart';
import 'widgets/desktop_sidebar.dart';
import 'widgets/status_indicator.dart';

/// App shell — v2.
///
/// Adaptive navigation scaffold:
/// - Desktop  (≥900dp): DesktopSidebar (240dp) + content
/// - Tablet   (600-900dp): NavigationRail (80dp) + content
/// - Mobile   (<600dp): NavigationBar + content
///
/// Mobile AppBar has been simplified to a centered title with status dot.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index =
        NavDestinations.all.indexWhere((d) => location.startsWith(d.path));
    return index >= 0 ? index : 0;
  }

  void _onDestinationSelected(BuildContext context, int index) {
    context.go(NavDestinations.all[index].path);
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentIndex(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        // ── Desktop ──────────────────────────────────────────────────
        if (width >= AppSpacing.tabletBreakpoint) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  DesktopSidebar(
                    currentIndex: currentIndex,
                    onDestinationSelected: (i) =>
                        _onDestinationSelected(context, i),
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          );
        }

        // ── Tablet ───────────────────────────────────────────────────
        if (width >= AppSpacing.mobileBreakpoint) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  _TabletRail(
                    currentIndex: currentIndex,
                    isDark: isDark,
                    onSelected: (i) => _onDestinationSelected(context, i),
                  ),
                  VerticalDivider(
                    width: 1,
                    color: isDark ? AppColors.darkBorder : AppColors.border,
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          );
        }

        // ── Mobile ───────────────────────────────────────────────────
        return Scaffold(
          appBar: AppBar(
            leading: const Padding(
              padding: EdgeInsets.only(left: AppSpacing.space4),
              child: Center(child: StatusIndicator()),
            ),
            title: Text(
              'SecureWave',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
            ),
            centerTitle: true,
          ),
          body: child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: (i) => _onDestinationSelected(context, i),
            destinations: NavDestinations.all
                .map((d) => NavigationDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: d.label,
                    ))
                .toList(),
          ),
        );
      },
    );
  }
}

// ── Tablet rail ───────────────────────────────────────────────────────────

class _TabletRail extends StatelessWidget {
  const _TabletRail({
    required this.currentIndex,
    required this.isDark,
    required this.onSelected,
  });

  final int currentIndex;
  final bool isDark;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.railWidth,
      color: isDark ? AppColors.darkBackground : AppColors.background,
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.space4),
          SvgPicture.asset(
            'assets/securewave_logo.svg',
            width: 28,
            height: 28,
          ),
          const SizedBox(height: AppSpacing.space2),
          Expanded(
            child: NavigationRail(
              selectedIndex: currentIndex,
              onDestinationSelected: onSelected,
              labelType: NavigationRailLabelType.all,
              backgroundColor: Colors.transparent,
              destinations: NavDestinations.all
                  .map((d) => NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                        padding: const EdgeInsets.symmetric(vertical: 2),
                      ))
                  .toList(),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.space4),
            child: StatusIndicator(),
          ),
        ],
      ),
    );
  }
}

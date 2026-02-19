import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../ui/design/app_spacing.dart';
import 'nav_destinations.dart';
import 'widgets/desktop_sidebar.dart';
import 'widgets/status_indicator.dart';

class AppShell extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = _currentIndex(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        // Desktop (>=900dp)
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

        // Tablet (600-900dp)
        if (width >= AppSpacing.mobileBreakpoint) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Column(
                      children: [
                        const SizedBox(height: AppSpacing.space4),
                        SvgPicture.asset(
                          'assets/securewave_logo.svg',
                          width: 32,
                          height: 32,
                        ),
                        const SizedBox(height: AppSpacing.space3),
                        Expanded(
                          child: NavigationRail(
                            selectedIndex: currentIndex,
                            onDestinationSelected: (i) =>
                                _onDestinationSelected(context, i),
                            labelType: NavigationRailLabelType.all,
                            backgroundColor: Colors.transparent,
                            destinations: NavDestinations.all
                                .map((d) => NavigationRailDestination(
                                      icon: Icon(d.icon),
                                      selectedIcon: Icon(d.selectedIcon),
                                      label: Text(d.label),
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
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: child),
                ],
              ),
            ),
          );
        }

        // Mobile (<600dp)
        return Scaffold(
          appBar: AppBar(
            leading: const Padding(
              padding: EdgeInsets.only(left: AppSpacing.space4),
              child: Center(child: StatusIndicator()),
            ),
            title: Text(
              'SecureWave',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            centerTitle: true,
          ),
          body: child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: (i) =>
                _onDestinationSelected(context, i),
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

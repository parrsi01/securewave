import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../ui/design/app_colors.dart';
import '../ui/design/app_spacing.dart';
import '../ui/design/app_animations.dart';
import '../core/models/vpn_status.dart';
import '../core/state/vpn_state.dart';
import 'nav_destinations.dart';

/// Adaptive app shell with bottom navigation (mobile) or rail (desktop).
///
/// Displays connection status and provides navigation between 4 main tabs:
/// Home, Locations, Settings, Account.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = NavDestinations.all.indexWhere((d) => location.startsWith(d.path));
    return index >= 0 ? index : 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = _currentIndex(context);
    final vpnState = ref.watch(vpnStateProvider);
    final statusColor = _statusColor(vpnState.status);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= AppSpacing.tabletBreakpoint;

        if (isDesktop) {
          // Desktop: NavigationRail
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  _DesktopRail(
                    currentIndex: currentIndex,
                    statusColor: statusColor,
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: child),
                ],
              ),
            ),
          );
        }

        // Mobile: Bottom NavigationBar
        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: AppAnimations.durationNormal,
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.space2),
                Text(
                  'SecureWave',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          body: child,
          bottomNavigationBar: NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: (index) =>
                context.go(NavDestinations.all[index].path),
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

  Color _statusColor(VpnStatus status) {
    switch (status) {
      case VpnStatus.connected:
        return AppColors.success;
      case VpnStatus.connecting:
      case VpnStatus.disconnecting:
        return AppColors.warning;
      case VpnStatus.error:
        return AppColors.error;
      case VpnStatus.disconnected:
        return AppColors.inkSoft;
    }
  }
}

/// Desktop navigation rail with logo and status indicator.
class _DesktopRail extends StatelessWidget {
  const _DesktopRail({
    required this.currentIndex,
    required this.statusColor,
  });

  final int currentIndex;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.space4),
          // Logo
          SvgPicture.asset(
            'assets/securewave_logo.svg',
            width: 32,
            height: 32,
          ),
          const SizedBox(height: AppSpacing.space2),
          // Status dot
          AnimatedContainer(
            duration: AppAnimations.durationNormal,
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: AppSpacing.space4),
          // Navigation items
          Expanded(
            child: NavigationRail(
              selectedIndex: currentIndex,
              onDestinationSelected: (index) =>
                  context.go(NavDestinations.all[index].path),
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
          const SizedBox(height: AppSpacing.space4),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_spacing.dart';

/// Adaptive navigation shell.
///
/// Mobile (< 600dp): NavigationBar at the bottom.
/// Desktop/tablet (≥ 600dp): NavigationRail on the left.
class AdaptiveShellScaffold extends StatelessWidget {
  const AdaptiveShellScaffold({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.public_outlined),
      selectedIcon: Icon(Icons.public_rounded),
      label: 'Servers',
    ),
    NavigationDestination(
      icon: Icon(Icons.shield_outlined),
      selectedIcon: Icon(Icons.shield_rounded),
      label: 'Connection',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: 'Settings',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outlined),
      selectedIcon: Icon(Icons.person_rounded),
      label: 'Account',
    ),
  ];

  static const _railDestinations = [
    NavigationRailDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: Text('Home'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.public_outlined),
      selectedIcon: Icon(Icons.public_rounded),
      label: Text('Servers'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.shield_outlined),
      selectedIcon: Icon(Icons.shield_rounded),
      label: Text('Connect'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: Text('Settings'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.person_outlined),
      selectedIcon: Icon(Icons.person_rounded),
      label: Text('Account'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= AppSpacing.mobileBreakpoint;

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: currentIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: _railDestinations,
              labelType: NavigationRailLabelType.selected,
              minWidth: AppSpacing.railWidth,
              groupAlignment: -0.8,
              backgroundColor: Theme.of(context).colorScheme.surface,
              indicatorColor: AppColors.primaryLight,
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: _destinations,
        height: 64,
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Navigation destinations for the app shell.
///
/// Defines the 4 main tabs: Home, Locations, Settings, Account.
class NavDestination {
  const NavDestination({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// The 4 main navigation destinations.
class NavDestinations {
  NavDestinations._();

  static const home = NavDestination(
    path: '/home',
    label: 'Home',
    icon: Icons.shield_outlined,
    selectedIcon: Icons.shield,
  );

  static const locations = NavDestination(
    path: '/locations',
    label: 'Locations',
    icon: Icons.public_outlined,
    selectedIcon: Icons.public,
  );

  static const settings = NavDestination(
    path: '/settings',
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  );

  static const account = NavDestination(
    path: '/account',
    label: 'Account',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
  );

  static const all = [
    home,
    locations,
    account,
    settings,
  ];
}

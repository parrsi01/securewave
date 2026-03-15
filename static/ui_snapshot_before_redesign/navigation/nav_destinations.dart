import 'package:flutter/material.dart';

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

class NavDestinations {
  NavDestinations._();

  static const home = NavDestination(
    path: '/home',
    label: 'Home',
    icon: Icons.shield_outlined,
    selectedIcon: Icons.shield_rounded,
  );

  static const servers = NavDestination(
    path: '/servers',
    label: 'Servers',
    icon: Icons.public_outlined,
    selectedIcon: Icons.public_rounded,
  );

  static const connection = NavDestination(
    path: '/connection',
    label: 'Connection',
    icon: Icons.hub_outlined,
    selectedIcon: Icons.hub_rounded,
  );

  static const settings = NavDestination(
    path: '/settings',
    label: 'Settings',
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune_rounded,
  );

  static const account = NavDestination(
    path: '/account',
    label: 'Account',
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
  );

  static const List<NavDestination> all = <NavDestination>[
    home,
    servers,
    connection,
    settings,
    account,
  ];
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_session.dart';
import '../utils/responsive.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _destinations = [
    _NavDestination('Dashboard', Icons.dashboard, '/dashboard'),
    _NavDestination('VPN', Icons.shield, '/vpn'),
    _NavDestination('Devices', Icons.devices, '/devices'),
    _NavDestination('Tests', Icons.speed, '/tests'),
    _NavDestination('Settings', Icons.settings, '/settings'),
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _destinations.indexWhere((d) => location.startsWith(d.route));
    return index >= 0 ? index : 0;
  }

  String _titleForRoute(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final match = _destinations.firstWhere(
      (d) => location.startsWith(d.route),
      orElse: () => _destinations.first,
    );
    return match.label;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = _currentIndex(context);
    final isDesktop = Responsive.isDesktop(context);
    final title = _titleForRoute(context);

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: currentIndex,
              onDestinationSelected: (index) => context.go(_destinations[index].route),
              labelType: NavigationRailLabelType.all,
              destinations: _destinations
                  .map((d) => NavigationRailDestination(
                        icon: Icon(d.icon),
                        label: Text(d.label),
                      ))
                  .toList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(title),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.logout),
                      onPressed: () async {
                        await ref.read(authSessionProvider).clearSession();
                        if (context.mounted) context.go('/login');
                      },
                    ),
                  ],
                ),
                body: child,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authSessionProvider).clearSession();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) => context.go(_destinations[index].route),
        items: _destinations
            .map((d) => BottomNavigationBarItem(icon: Icon(d.icon), label: d.label))
            .toList(),
      ),
    );
  }
}

class _NavDestination {
  const _NavDestination(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;
}

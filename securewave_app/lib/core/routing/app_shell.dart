import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ui/app_ui_v1.dart';
import '../services/auth_session.dart';
import '../services/app_state.dart';
import '../services/vpn_service.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _destinations = [
    _NavDestination('Connect', Icons.shield, '/vpn'),
    _NavDestination('Servers', Icons.public, '/servers'),
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
    final title = _titleForRoute(context);
    final vpnStatus = ref.watch(vpnStatusProvider);

    final statusChip = vpnStatus.when(
      data: (status) {
        final label = status == VpnStatus.connected
            ? 'Connected'
            : status == VpnStatus.connecting
                ? 'Connecting'
                : status == VpnStatus.disconnecting
                    ? 'Disconnecting'
                    : 'Disconnected';
        final color = status == VpnStatus.connected
            ? AppUIv1.success
            : status == VpnStatus.disconnected
                ? AppUIv1.inkSoft
                : AppUIv1.accentSun;
        return Chip(
          label: Text(label),
          backgroundColor: color.withValues(alpha: 0.15),
          labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        );
      },
      loading: () => const Chip(label: Text('Checking')),
      error: (_, __) => const Chip(label: Text('Unavailable')),
    );

    Widget buildScaffold({Widget? bottomNavigation}) {
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            statusChip,
            const SizedBox(width: AppUIv1.space2),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await ref.read(authSessionProvider).clearSession();
                if (context.mounted) context.go('/login');
              },
            ),
            const SizedBox(width: AppUIv1.space2),
          ],
        ),
        body: SafeArea(child: child),
        bottomNavigationBar: bottomNavigation,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return buildScaffold(
            bottomNavigation: NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: (index) => context.go(_destinations[index].route),
              destinations: _destinations
                  .map((d) => NavigationDestination(icon: Icon(d.icon), label: d.label))
                  .toList(),
            ),
          );
        }

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: currentIndex,
                  onDestinationSelected: (index) => context.go(_destinations[index].route),
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: AppUIv1.background,
                  destinations: _destinations
                      .map((d) => NavigationRailDestination(
                            icon: Icon(d.icon),
                            label: Text(d.label),
                          ))
                      .toList(),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: buildScaffold()),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NavDestination {
  const _NavDestination(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;
}

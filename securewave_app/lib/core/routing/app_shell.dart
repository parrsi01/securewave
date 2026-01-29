import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ui/app_ui_v1.dart';
import '../../services/external_links.dart';
import '../config/app_config.dart';
import '../services/auth_session.dart';
import '../models/vpn_status.dart';
import '../state/vpn_state.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _destinations = [
    _NavDestination('Home', Icons.shield, '/vpn'),
    _NavDestination('Servers', Icons.public, '/servers'),
    _NavDestination('Account', Icons.person, '/account'),
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
    final vpnState = ref.watch(vpnStateProvider);
    final config = ref.watch(appConfigProvider);

    final statusLabel = switch (vpnState.status) {
      VpnStatus.connected => 'Connected',
      VpnStatus.connecting => 'Connecting',
      VpnStatus.error => 'Needs attention',
      VpnStatus.disconnected => 'Disconnected',
    };
    final statusColor = switch (vpnState.status) {
      VpnStatus.connected => AppUIv1.success,
      VpnStatus.connecting => AppUIv1.accentSun,
      VpnStatus.error => AppUIv1.warning,
      VpnStatus.disconnected => AppUIv1.inkSoft,
    };
    final statusChip = Chip(
      label: Text(statusLabel),
      backgroundColor: statusColor.withValues(alpha: 0.15),
      labelStyle: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );

    void handleNavigation(String route) {
      Navigator.of(context).maybePop();
      context.go(route);
    }

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
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppUIv1.space4),
              children: [
                Text('SecureWave', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppUIv1.space4),
                ListTile(
                  leading: const Icon(Icons.shield),
                  title: const Text('VPN Home'),
                  onTap: () => handleNavigation('/vpn'),
                ),
                ListTile(
                  leading: const Icon(Icons.public),
                  title: const Text('Server selection'),
                  onTap: () => handleNavigation('/servers'),
                ),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('VPN settings'),
                  onTap: () => handleNavigation('/settings'),
                ),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: const Text('Language'),
                  onTap: () {
                    Navigator.of(context).maybePop();
                    context.push('/settings/language');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('Account settings'),
                  onTap: () => handleNavigation('/account'),
                ),
                ListTile(
                  leading: const Icon(Icons.upgrade),
                  title: const Text('Plan & upgrade'),
                  onTap: () => ref.read(externalLinksProvider).openUrl(config.upgradeUrl),
                ),
                ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: const Text('Manage account'),
                  onTap: () => ref.read(externalLinksProvider).openUrl(config.portalUrl),
                ),
                const Divider(height: 24),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Logout'),
                  onTap: () async {
                    await ref.read(authSessionProvider).clearSession();
                    if (context.mounted) context.go('/login');
                  },
                ),
              ],
            ),
          ),
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

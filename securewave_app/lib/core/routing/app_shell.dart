import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/external_links.dart';
import '../../ui/app_ui_v1.dart';
import '../config/app_config.dart';
import '../models/vpn_status.dart';
import '../services/auth_session.dart';
import '../state/vpn_state.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _destinations = [
    _NavDestination('Home', Icons.home_rounded, '/vpn'),
    _NavDestination('Connection', Icons.wifi_tethering_rounded, '/connection'),
    _NavDestination('Servers', Icons.public_rounded, '/servers'),
    _NavDestination(
        'Diagnostics', Icons.health_and_safety_rounded, '/diagnostics'),
    _NavDestination('Account', Icons.person_rounded, '/account'),
    _NavDestination('Settings', Icons.tune_rounded, '/settings'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex =
        _destinations.indexWhere((item) => location.startsWith(item.route));
    final vpnState = ref.watch(vpnStateProvider);
    final config = ref.watch(appConfigProvider);

    final statusLabel = switch (vpnState.status) {
      VpnStatus.connected => 'Connected',
      VpnStatus.connecting => 'Connecting',
      VpnStatus.disconnecting => 'Disconnecting',
      VpnStatus.reconnecting => 'Reconnecting',
      VpnStatus.error => 'Error',
      VpnStatus.disconnected => 'Disconnected',
    };

    final statusColor = switch (vpnState.status) {
      VpnStatus.connected => AppUIv1.success,
      VpnStatus.connecting => AppUIv1.accentSun,
      VpnStatus.disconnecting => AppUIv1.accentSun,
      VpnStatus.reconnecting => AppUIv1.accentSun,
      VpnStatus.error => AppUIv1.danger,
      VpnStatus.disconnected => AppUIv1.inkSoft,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final rail = NavigationRail(
          selectedIndex: currentIndex < 0 ? 0 : currentIndex,
          onDestinationSelected: (index) =>
              context.go(_destinations[index].route),
          groupAlignment: -0.9,
          backgroundColor: AppUIv1.backgroundStrong,
          destinations: [
            for (final destination in _destinations)
              NavigationRailDestination(
                icon: Icon(destination.icon),
                label: Text(destination.label),
              ),
          ],
          trailing: Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(AppUIv1.space3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => ref
                          .read(externalLinksProvider)
                          .openUrl(config.portalUrl),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Portal'),
                    ),
                    const SizedBox(height: AppUIv1.space2),
                    TextButton(
                      onPressed: () async {
                        await ref.read(authSessionProvider).clearSession();
                        if (context.mounted) {
                          context.go('/login');
                        }
                      },
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final appBar = AppBar(
          title: const Text('SecureWave'),
          actions: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: AppUIv1.space2),
              padding: const EdgeInsets.symmetric(horizontal: AppUIv1.space3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Center(
                child: Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
            const SizedBox(width: AppUIv1.space3),
          ],
        );

        if (constraints.maxWidth < 1024) {
          const compactDestinations = [
            _NavDestination('Home', Icons.home_rounded, '/vpn'),
            _NavDestination(
                'Connection', Icons.wifi_tethering_rounded, '/connection'),
            _NavDestination('Servers', Icons.public_rounded, '/servers'),
            _NavDestination('Settings', Icons.tune_rounded, '/settings'),
          ];
          final compactIndex = compactDestinations.indexWhere(
            (item) => location.startsWith(item.route),
          );
          return Scaffold(
            appBar: appBar,
            body: child,
            bottomNavigationBar: NavigationBar(
              selectedIndex: compactIndex < 0 ? 0 : compactIndex,
              onDestinationSelected: (index) =>
                  context.go(compactDestinations[index].route),
              destinations: [
                for (final destination in compactDestinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    label: destination.label,
                  ),
              ],
            ),
            drawer: Drawer(
              backgroundColor: AppUIv1.backgroundStrong,
              child: rail,
            ),
          );
        }

        return Scaffold(
          appBar: appBar,
          body: Row(
            children: [
              rail,
              const VerticalDivider(width: 1),
              Expanded(child: child),
            ],
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_session.dart';
import '../services/app_state.dart';
import '../services/vpn_service.dart';
import '../../widgets/cards/status_chip.dart';
import '../../widgets/layouts/app_background.dart';
import '../utils/responsive.dart';
import '../../widgets/layouts/brand_logo.dart';

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
            ? const Color(0xFF10B981)
            : status == VpnStatus.connecting
                ? const Color(0xFF38BDF8)
                : status == VpnStatus.disconnecting
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF94A3B8);
        return StatusChip(label: label, color: color);
      },
      loading: () => const StatusChip(label: 'Checking', color: Color(0xFF94A3B8)),
      error: (_, __) => const StatusChip(label: 'Unavailable', color: Color(0xFF94A3B8)),
    );

    if (isDesktop) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final extendRail = constraints.maxWidth >= 1200;
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: currentIndex,
                  onDestinationSelected: (index) => context.go(_destinations[index].route),
                  labelType: extendRail ? null : NavigationRailLabelType.all,
                  extended: extendRail,
                  minWidth: 72,
                  minExtendedWidth: 200,
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
                      title: Row(
                        children: [
                          const BrandLogo(size: 20),
                          const SizedBox(width: 10),
                          Flexible(child: Text(title)),
                        ],
                      ),
                      actions: [
                        statusChip,
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.logout),
                          onPressed: () async {
                            await ref.read(authSessionProvider).clearSession();
                            if (context.mounted) context.go('/login');
                          },
                        ),
                      ],
                    ),
                    body: AppBackground(child: child),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const BrandLogo(size: 18),
            const SizedBox(width: 10),
            Flexible(child: Text(title)),
          ],
        ),
        actions: [
          statusChip,
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authSessionProvider).clearSession();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: AppBackground(child: child),
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

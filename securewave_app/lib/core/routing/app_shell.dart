import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/external_links.dart';
import '../../ui/app_ui_v1.dart';
import '../../ui/securewave_ui.dart';
import '../config/app_config.dart';
import '../models/vpn_status.dart';
import '../services/auth_session.dart';
import '../state/vpn_state.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _destinations = [
    _NavDestination(
      'Dashboard',
      Icons.dashboard_outlined,
      Icons.dashboard_rounded,
      '/vpn',
    ),
    _NavDestination(
      'Locations',
      Icons.travel_explore,
      Icons.public_rounded,
      '/servers',
    ),
    _NavDestination(
      'Account',
      Icons.person_outline_rounded,
      Icons.person,
      '/account',
    ),
    _NavDestination(
      'Settings',
      Icons.tune_rounded,
      Icons.settings,
      '/settings',
    ),
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _destinations.indexWhere((d) => location.startsWith(d.route));
    return index >= 0 ? index : 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = _currentIndex(context);
    final vpnState = ref.watch(vpnStateProvider);
    final config = ref.watch(appConfigProvider);
    final statusColor = _statusColor(vpnState);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= AppUIv1.tabletBreakpoint;
        if (isDesktop) {
          return Scaffold(
            body: SwSecurityBackdrop(
              child: SafeArea(
                child: Row(
                  children: [
                    _DesktopSidebar(
                      currentIndex: currentIndex,
                      vpnStatus: vpnState.status,
                      statusColor: statusColor,
                      onLogout: () => _logout(context, ref),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: AppUIv1.durationNormal,
                        switchInCurve: AppUIv1.curveEnter,
                        switchOutCurve: AppUIv1.curveExit,
                        child: KeyedSubtree(
                          key: ValueKey(
                            GoRouterState.of(context).matchedLocation,
                          ),
                          child: child,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final location = GoRouterState.of(context).matchedLocation;
        final isNestedRoute =
            location.startsWith('/settings/') && location != '/settings';
        return Scaffold(
          appBar: isNestedRoute
              ? null
              : AppBar(
                  titleSpacing: AppUIv1.space4,
                  title: const SwBrandLockup(compact: true),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: AppUIv1.space2),
                      child: SwStatusPill(
                        label: _statusLabel(vpnState.status),
                        color: statusColor,
                        pulse: vpnState.status == VpnStatus.connecting ||
                            vpnState.status == VpnStatus.disconnecting,
                      ),
                    ),
                  ],
                ),
          drawer: isNestedRoute
              ? null
              : _MobileDrawer(
                  config: config,
                  vpnStatus: vpnState.status,
                  statusColor: statusColor,
                  onLogout: () => _logout(context, ref),
                  onNavigate: (route) {
                    Navigator.of(context).maybePop();
                    context.go(route);
                  },
                  onExternalLink: (url) =>
                      ref.read(externalLinksProvider).openUrl(url),
                ),
          body: child,
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              color: AppUIv1.backgroundStrong,
              border: Border(
                top: BorderSide(color: AppUIv1.border.withValues(alpha: 0.8)),
              ),
            ),
            child: NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: (index) =>
                  context.go(_destinations[index].route),
              destinations: _destinations
                  .map(
                    (d) => NavigationDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: d.label,
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }

  Color _statusColor(VpnState vpnState) {
    final backendUnreachable = vpnState.status == VpnStatus.error &&
        vpnState.errorKind == VpnErrorKind.backendUnreachable;
    return switch (vpnState.status) {
      VpnStatus.connected => AppUIv1.success,
      VpnStatus.connecting => AppUIv1.accentCyan,
      VpnStatus.disconnecting => AppUIv1.warning,
      VpnStatus.error => backendUnreachable ? AppUIv1.danger : AppUIv1.warning,
      VpnStatus.disconnected => AppUIv1.inkSoft,
    };
  }

  String _statusLabel(VpnStatus status) {
    return switch (status) {
      VpnStatus.connected => 'Secure',
      VpnStatus.connecting => 'Linking',
      VpnStatus.disconnecting => 'Closing',
      VpnStatus.error => 'Alert',
      VpnStatus.disconnected => 'Idle',
    };
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(authSessionProvider).clearSession();
    if (context.mounted) context.go('/login');
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.currentIndex,
    required this.vpnStatus,
    required this.statusColor,
    required this.onLogout,
  });

  final int currentIndex;
  final VpnStatus vpnStatus;
  final Color statusColor;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      margin: const EdgeInsets.all(AppUIv1.space3),
      decoration: BoxDecoration(
        color: AppUIv1.surfaceGlass,
        borderRadius: BorderRadius.circular(AppUIv1.radiusL),
        border: Border.all(color: AppUIv1.border),
        boxShadow: AppUIv1.shadowMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppUIv1.space5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SwBrandLockup(),
                const SizedBox(height: AppUIv1.space4),
                SwStatusPill(
                  label: switch (vpnStatus) {
                    VpnStatus.connected => 'Protected tunnel active',
                    VpnStatus.connecting => 'Negotiating tunnel',
                    VpnStatus.disconnecting => 'Closing tunnel',
                    VpnStatus.error => 'Action required',
                    VpnStatus.disconnected => 'Tunnel idle',
                  },
                  color: statusColor,
                  pulse: vpnStatus == VpnStatus.connecting ||
                      vpnStatus == VpnStatus.disconnecting,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: AppUIv1.space3),
              itemBuilder: (context, index) {
                final destination = AppShell._destinations[index];
                final selected = index == currentIndex;
                return _DesktopNavItem(
                  destination: destination,
                  selected: selected,
                  onTap: () => context.go(destination.route),
                );
              },
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppUIv1.space2),
              itemCount: AppShell._destinations.length,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppUIv1.space3),
            child: SwActionTile(
              icon: Icons.logout_rounded,
              title: 'Sign out',
              subtitle: 'Clear local session',
              color: AppUIv1.inkSoft,
              onTap: onLogout,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopNavItem extends StatelessWidget {
  const _DesktopNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SwPanel(
      onTap: onTap,
      selected: selected,
      accent: AppUIv1.accentCyan,
      padding: const EdgeInsets.symmetric(
        horizontal: AppUIv1.space3,
        vertical: AppUIv1.space3,
      ),
      child: Row(
        children: [
          Icon(
            selected ? destination.selectedIcon : destination.icon,
            color: selected ? AppUIv1.accentCyan : AppUIv1.inkSoft,
            size: 20,
          ),
          const SizedBox(width: AppUIv1.space3),
          Expanded(
            child: Text(
              destination.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? AppUIv1.ink : AppUIv1.inkMuted,
                  ),
            ),
          ),
          AnimatedOpacity(
            duration: AppUIv1.durationFast,
            opacity: selected ? 1 : 0,
            child: const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppUIv1.accentCyan,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileDrawer extends StatelessWidget {
  const _MobileDrawer({
    required this.config,
    required this.vpnStatus,
    required this.statusColor,
    required this.onLogout,
    required this.onNavigate,
    required this.onExternalLink,
  });

  final AppConfig config;
  final VpnStatus vpnStatus;
  final Color statusColor;
  final VoidCallback onLogout;
  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onExternalLink;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppUIv1.backgroundStrong,
      child: SwSecurityBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppUIv1.space4),
            child: Column(
              children: [
                SwPanel(
                  accent: statusColor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SwBrandLockup(),
                      const SizedBox(height: AppUIv1.space4),
                      SwStatusPill(
                        label: switch (vpnStatus) {
                          VpnStatus.connected => 'Protected',
                          VpnStatus.connecting => 'Negotiating',
                          VpnStatus.disconnecting => 'Closing',
                          VpnStatus.error => 'Needs attention',
                          VpnStatus.disconnected => 'Disconnected',
                        },
                        color: statusColor,
                        pulse: vpnStatus == VpnStatus.connecting ||
                            vpnStatus == VpnStatus.disconnecting,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppUIv1.space4),
                Expanded(
                  child: ListView(
                    children: [
                      _drawerTile(
                        Icons.dashboard_rounded,
                        'Dashboard',
                        () => onNavigate('/vpn'),
                      ),
                      _drawerTile(
                        Icons.travel_explore,
                        'Locations',
                        () => onNavigate('/servers'),
                      ),
                      _drawerTile(
                        Icons.person,
                        'Account',
                        () => onNavigate('/account'),
                      ),
                      _drawerTile(
                        Icons.tune_rounded,
                        'Settings',
                        () => onNavigate('/settings'),
                      ),
                      const SizedBox(height: AppUIv1.space3),
                      _drawerTile(Icons.language, 'Language', () {
                        Navigator.of(context).maybePop();
                        context.push('/settings/language');
                      }),
                      _drawerTile(
                        Icons.upgrade_rounded,
                        'Upgrade plan',
                        () => onExternalLink(config.upgradeUrl),
                      ),
                      _drawerTile(
                        Icons.open_in_new,
                        'Web portal',
                        () => onExternalLink(config.portalUrl),
                      ),
                    ],
                  ),
                ),
                SwActionTile(
                  icon: Icons.logout_rounded,
                  title: 'Sign out',
                  subtitle: 'Clear local session',
                  color: AppUIv1.inkSoft,
                  onTap: onLogout,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _drawerTile(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppUIv1.space2),
      child: SwPanel(
        padding: const EdgeInsets.symmetric(
          horizontal: AppUIv1.space3,
          vertical: AppUIv1.space3,
        ),
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: AppUIv1.accentCyan, size: 20),
            const SizedBox(width: AppUIv1.space3),
            Expanded(
              child: Builder(
                builder: (context) =>
                    Text(label, style: Theme.of(context).textTheme.labelLarge),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavDestination {
  const _NavDestination(this.label, this.icon, this.selectedIcon, this.route);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String route;
}

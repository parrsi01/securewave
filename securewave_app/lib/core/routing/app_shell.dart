import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
    _NavDestination('Home', Icons.shield_outlined, Icons.shield, '/vpn'),
    _NavDestination('Servers', Icons.public_outlined, Icons.public, '/servers'),
    _NavDestination('Account', Icons.person_outline, Icons.person, '/account'),
    _NavDestination(
        'Settings', Icons.settings_outlined, Icons.settings, '/settings'),
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

    final backendUnreachable = vpnState.status == VpnStatus.error &&
        vpnState.errorKind == VpnErrorKind.backendUnreachable;
    final statusLabel = vpnState.statusText();

    final statusColor = switch (vpnState.status) {
      VpnStatus.connected => AppUIv1.success,
      VpnStatus.connecting => AppUIv1.accentSun,
      VpnStatus.disconnecting => AppUIv1.accentSun,
      VpnStatus.error => backendUnreachable ? AppUIv1.danger : AppUIv1.warning,
      VpnStatus.disconnected => AppUIv1.inkSoft,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= AppUIv1.tabletBreakpoint;

        if (isDesktop) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  // Desktop: NavigationRail with logo header
                  _DesktopRail(
                    currentIndex: currentIndex,
                    statusColor: statusColor,
                    vpnStatus: vpnState.status,
                    onLogout: () => _logout(context, ref),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: child),
                ],
              ),
            ),
          );
        }

        // Mobile: bottom nav + drawer
        final location = GoRouterState.of(context).matchedLocation;
        final isNestedRoute =
            location.startsWith('/settings/') && location != '/settings';
        return Scaffold(
          appBar: isNestedRoute
              ? null
              : AppBar(
                  title: AnimatedSwitcher(
                    duration: AppUIv1.durationFast,
                    child: Row(
                      key: ValueKey(vpnState.status),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: AppUIv1.durationNormal,
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppUIv1.space2),
                        Text(
                          'SecureWave',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.logout, size: 20),
                      tooltip: 'Sign out',
                      onPressed: () => _logout(context, ref),
                    ),
                    const SizedBox(width: AppUIv1.space1),
                  ],
                ),
          drawer: isNestedRoute
              ? null
              : _AppDrawer(
                  config: config,
                  vpnStatus: vpnState.status,
                  statusLabel: statusLabel,
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
          bottomNavigationBar: NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: (index) =>
                context.go(_destinations[index].route),
            destinations: _destinations
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

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(authSessionProvider).clearSession();
    if (context.mounted) context.go('/login');
  }
}

// ── Desktop NavigationRail with branding ──────────────────────────────

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({
    required this.currentIndex,
    required this.statusColor,
    required this.vpnStatus,
    required this.onLogout,
  });

  final int currentIndex;
  final Color statusColor;
  final VpnStatus vpnStatus;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: Column(
        children: [
          const SizedBox(height: AppUIv1.space4),
          // Logo
          SvgPicture.asset(
            'assets/securewave_logo.svg',
            width: 32,
            height: 32,
          ),
          const SizedBox(height: AppUIv1.space2),
          // Status dot
          AnimatedContainer(
            duration: AppUIv1.durationNormal,
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: AppUIv1.space4),
          // Navigation items
          Expanded(
            child: NavigationRail(
              selectedIndex: currentIndex,
              onDestinationSelected: (index) =>
                  context.go(AppShell._destinations[index].route),
              labelType: NavigationRailLabelType.all,
              backgroundColor: Colors.transparent,
              destinations: AppShell._destinations
                  .map((d) => NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                      ))
                  .toList(),
            ),
          ),
          // Logout at bottom
          IconButton(
            icon: const Icon(Icons.logout, size: 20, color: AppUIv1.inkSoft),
            tooltip: 'Sign out',
            onPressed: onLogout,
          ),
          const SizedBox(height: AppUIv1.space4),
        ],
      ),
    );
  }
}

// ── Mobile Drawer ─────────────────────────────────────────────────────

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.config,
    required this.vpnStatus,
    required this.statusLabel,
    required this.statusColor,
    required this.onLogout,
    required this.onNavigate,
    required this.onExternalLink,
  });

  final AppConfig config;
  final VpnStatus vpnStatus;
  final String statusLabel;
  final Color statusColor;
  final VoidCallback onLogout;
  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onExternalLink;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(AppUIv1.space5),
              child: Row(
                children: [
                  SvgPicture.asset(
                    'assets/securewave_logo.svg',
                    width: 36,
                    height: 36,
                  ),
                  const SizedBox(width: AppUIv1.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SecureWave',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              statusLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: statusColor),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Navigation
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: AppUIv1.space2),
                children: [
                  _drawerTile(context, Icons.shield, 'VPN Home',
                      () => onNavigate('/vpn')),
                  _drawerTile(context, Icons.public, 'Servers',
                      () => onNavigate('/servers')),
                  _drawerTile(context, Icons.person, 'Account',
                      () => onNavigate('/account')),
                  _drawerTile(context, Icons.settings, 'Settings',
                      () => onNavigate('/settings')),
                  const Divider(height: AppUIv1.space5),
                  _drawerTile(
                    context,
                    Icons.language,
                    'Language',
                    () {
                      Navigator.of(context).maybePop();
                      context.push('/settings/language');
                    },
                  ),
                  _drawerTile(
                    context,
                    Icons.upgrade,
                    'Upgrade plan',
                    () => onExternalLink(config.upgradeUrl),
                  ),
                  _drawerTile(
                    context,
                    Icons.open_in_new,
                    'Web portal',
                    () => onExternalLink(config.portalUrl),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Logout
            ListTile(
              leading: const Icon(Icons.logout, color: AppUIv1.inkSoft),
              title: Text(
                'Sign out',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              onTap: onLogout,
            ),
            const SizedBox(height: AppUIv1.space2),
          ],
        ),
      ),
    );
  }

  Widget _drawerTile(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, size: 22),
      title: Text(label),
      dense: true,
      onTap: onTap,
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

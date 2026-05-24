import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../ui/app_ui_v1.dart';
import '../../services/external_links.dart';
import '../config/app_config.dart';
import '../services/auth_session.dart';
import '../models/vpn_status.dart';
import '../state/app_state.dart';
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
    final account = ref.watch(currentUserProvider);
    final accountLabel = account.maybeWhen(
      data: (user) => user.email.isEmpty ? 'Signed in' : user.email,
      loading: () => 'Loading account',
      orElse: () => 'Account unavailable',
    );

    final backendUnreachable = vpnState.status == VpnStatus.error &&
        vpnState.errorKind == VpnErrorKind.backendUnreachable;

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
            body: SecurePageBackground(
              child: SafeArea(
                child: Row(
                  children: [
                    _DesktopRail(
                      currentIndex: currentIndex,
                      statusColor: statusColor,
                      vpnStatus: vpnState.status,
                      accountLabel: accountLabel,
                      onLogout: () => _logout(context, ref),
                    ),
                    Expanded(child: child),
                  ],
                ),
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
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppUIv1.surfaceRaised,
                            borderRadius:
                                BorderRadius.circular(AppUIv1.radiusXS),
                            border: Border.all(color: AppUIv1.border),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: SvgPicture.asset(
                              'assets/securewave_logo.svg',
                            ),
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
                  statusColor: statusColor,
                  accountLabel: accountLabel,
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
              color: AppUIv1.surface.withValues(alpha: 0.98),
              border: const Border(top: BorderSide(color: AppUIv1.divider)),
            ),
            child: NavigationBar(
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

// ── Desktop navigation rail with branding ──────────────────────────────

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({
    required this.currentIndex,
    required this.statusColor,
    required this.vpnStatus,
    required this.accountLabel,
    required this.onLogout,
  });

  final int currentIndex;
  final Color statusColor;
  final VpnStatus vpnStatus;
  final String accountLabel;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (vpnStatus) {
      VpnStatus.connected => 'Connected',
      VpnStatus.connecting => 'Connecting',
      VpnStatus.disconnecting => 'Disconnecting',
      VpnStatus.error => 'Needs attention',
      VpnStatus.disconnected => 'Disconnected',
    };

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppUIv1.backgroundStrong,
        border: Border(right: BorderSide(color: AppUIv1.divider)),
      ),
      child: SizedBox(
        width: 248,
        child: Padding(
          padding: const EdgeInsets.all(AppUIv1.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppUIv1.surfaceRaised,
                      borderRadius: BorderRadius.circular(AppUIv1.radiusS),
                      border: Border.all(color: AppUIv1.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppUIv1.space2),
                      child: SvgPicture.asset(
                        'assets/securewave_logo.svg',
                        width: 28,
                        height: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppUIv1.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SecureWave',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppUIv1.space1),
                        Text(
                          accountLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppUIv1.inkSoft,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppUIv1.space4),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppUIv1.surface,
                  borderRadius: BorderRadius.circular(AppUIv1.radiusS),
                  border: Border.all(color: AppUIv1.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppUIv1.space3,
                    vertical: AppUIv1.space2,
                  ),
                  child: Row(
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
                      Expanded(
                        child: Text(
                          statusLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppUIv1.inkMuted,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppUIv1.space5),
              Expanded(
                child: Column(
                  children: [
                    for (var i = 0; i < AppShell._destinations.length; i++) ...[
                      _RailButton(
                        destination: AppShell._destinations[i],
                        selected: i == currentIndex,
                        onTap: () =>
                            context.go(AppShell._destinations[i].route),
                      ),
                      if (i != AppShell._destinations.length - 1)
                        const SizedBox(height: AppUIv1.space1),
                    ],
                  ],
                ),
              ),
              const Divider(),
              const SizedBox(height: AppUIv1.space2),
              _RailButton(
                destination: const _NavDestination(
                  'Sign out',
                  Icons.logout_rounded,
                  Icons.logout_rounded,
                  '',
                ),
                selected: false,
                color: AppUIv1.inkSoft,
                onTap: onLogout,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.destination,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final _NavDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? (selected ? AppUIv1.ink : AppUIv1.inkMuted);
    final background = selected ? AppUIv1.accent : Colors.transparent;
    final border = selected ? AppUIv1.accent : Colors.transparent;

    return Tooltip(
      message: destination.label,
      waitDuration: const Duration(milliseconds: 450),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppUIv1.radiusS),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppUIv1.radiusS),
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppUIv1.durationFast,
            curve: AppUIv1.curveDefault,
            padding: const EdgeInsets.symmetric(
              horizontal: AppUIv1.space3,
              vertical: AppUIv1.space3,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppUIv1.radiusS),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  color: foreground,
                  size: 20,
                ),
                const SizedBox(width: AppUIv1.space3),
                Expanded(
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: foreground,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mobile Drawer ─────────────────────────────────────────────────────

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.config,
    required this.vpnStatus,
    required this.statusColor,
    required this.accountLabel,
    required this.onLogout,
    required this.onNavigate,
    required this.onExternalLink,
  });

  final AppConfig config;
  final VpnStatus vpnStatus;
  final Color statusColor;
  final String accountLabel;
  final VoidCallback onLogout;
  final ValueChanged<String> onNavigate;
  final ValueChanged<String> onExternalLink;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final statusLabel = switch (vpnStatus) {
      VpnStatus.connected => 'Connected',
      VpnStatus.connecting => 'Connecting',
      VpnStatus.disconnecting => 'Disconnecting',
      VpnStatus.error => 'Needs attention',
      VpnStatus.disconnected => 'Disconnected',
    };

    return Drawer(
      backgroundColor: AppUIv1.backgroundStrong,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppUIv1.space4),
              child: SecureSurface(
                variant: SecureSurfaceVariant.glass,
                radius: AppUIv1.radiusXL,
                padding: const EdgeInsets.all(AppUIv1.space4),
                child: Row(
                  children: [
                    SvgPicture.asset(
                      'assets/securewave_logo.svg',
                      width: 38,
                      height: 38,
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
                          const SizedBox(height: AppUIv1.space1),
                          Text(
                            accountLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppUIv1.inkSoft,
                                    ),
                          ),
                          const SizedBox(height: AppUIv1.space2),
                          SecureStatePill(
                            label: statusLabel,
                            color: statusColor,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppUIv1.space4,
                  0,
                  AppUIv1.space4,
                  AppUIv1.space4,
                ),
                children: [
                  for (final destination in AppShell._destinations) ...[
                    _DrawerAction(
                      icon: location.startsWith(destination.route)
                          ? destination.selectedIcon
                          : destination.icon,
                      label: destination.label == 'Home'
                          ? 'VPN Home'
                          : destination.label,
                      selected: location.startsWith(destination.route),
                      onTap: () => onNavigate(destination.route),
                    ),
                    const SizedBox(height: AppUIv1.space2),
                  ],
                  const SizedBox(height: AppUIv1.space2),
                  const Divider(height: AppUIv1.space4),
                  const SizedBox(height: AppUIv1.space2),
                  _DrawerAction(
                    icon: Icons.language_rounded,
                    label: 'Language',
                    onTap: () {
                      Navigator.of(context).maybePop();
                      context.push('/settings/language');
                    },
                  ),
                  const SizedBox(height: AppUIv1.space2),
                  _DrawerAction(
                    icon: Icons.workspace_premium_outlined,
                    label: 'Premium updates',
                    onTap: () => onExternalLink(config.upgradeUrl),
                  ),
                  const SizedBox(height: AppUIv1.space2),
                  _DrawerAction(
                    icon: Icons.open_in_new_rounded,
                    label: 'Web portal',
                    onTap: () => onExternalLink(config.portalUrl),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppUIv1.space4,
                0,
                AppUIv1.space4,
                AppUIv1.space4,
              ),
              child: _DrawerAction(
                icon: Icons.logout_rounded,
                label: 'Sign out',
                color: AppUIv1.inkSoft,
                onTap: onLogout,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerAction extends StatelessWidget {
  const _DrawerAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? (selected ? AppUIv1.ink : AppUIv1.inkMuted);

    return SecureSurface(
      variant:
          selected ? SecureSurfaceVariant.accent : SecureSurfaceVariant.base,
      padding: const EdgeInsets.symmetric(
        horizontal: AppUIv1.space3,
        vertical: AppUIv1.space3,
      ),
      radius: AppUIv1.radiusL,
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: foreground, size: 21),
          const SizedBox(width: AppUIv1.space3),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
            ),
          ),
          if (selected)
            const Icon(
              Icons.radio_button_checked_rounded,
              color: AppUIv1.ink,
              size: 15,
            ),
        ],
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

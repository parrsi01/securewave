import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/models/vpn_status.dart';
import 'core/services/auth_session.dart';
import 'core/state/app_state.dart';
import 'core/state/vpn_state.dart';
import 'core/utils/api_error.dart';
import 'services/auth_service.dart';
import 'services/api_client.dart';
import 'ui/app_ui_v1.dart';

class SecureWaveApp extends ConsumerWidget {
  const SecureWaveApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'SecureWave',
      debugShowCheckedModeBanner: false,
      theme: AppUIv1.theme,
      home: const _AppRoot(),
    );
  }
}

class _AppRoot extends ConsumerWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    final config = ref.watch(appConfigProvider);
    if (!session.isInitialized) return const _LoadingView();
    if (!session.isAuthenticated) return const _AuthView();
    return _HomeView(isDemo: config.demoMode);
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: AppProgressIndicator(label: 'Loading SecureWave')),
    );
  }
}

class _AuthView extends ConsumerStatefulWidget {
  const _AuthView();

  @override
  ConsumerState<_AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends ConsumerState<_AuthView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _BrandMark(),
                  const SizedBox(height: 32),
                  Text(
                    _register
                        ? 'Create your SecureWave account'
                        : 'Welcome back',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _register
                        ? 'One account for your Linux WireGuard beta.'
                        : 'Sign in to connect to SecureWave Beta.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (config.demoMode) ...[
                    const SizedBox(height: 14),
                    const _DemoBanner(),
                  ],
                  const SizedBox(height: 24),
                  AppPanel(
                    child: Form(
                      key: _formKey,
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _email,
                              autofillHints: const [AutofillHints.email],
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration:
                                  const InputDecoration(labelText: 'Email'),
                              validator: (value) {
                                if (value == null || !value.contains('@')) {
                                  return 'Enter a valid email.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _password,
                              obscureText: _hidePassword,
                              autofillHints: [
                                _register
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password,
                              ],
                              textInputAction: _register
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                suffixIcon: IconButton(
                                  tooltip: _hidePassword
                                      ? 'Show password'
                                      : 'Hide password',
                                  onPressed: () => setState(
                                      () => _hidePassword = !_hidePassword),
                                  icon: Icon(_hidePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined),
                                ),
                              ),
                              validator: (value) =>
                                  value == null || value.length < 8
                                      ? 'Use at least 8 characters.'
                                      : null,
                            ),
                            if (_register) ...[
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _confirm,
                                obscureText: true,
                                decoration: const InputDecoration(
                                    labelText: 'Confirm password'),
                                validator: (value) => value != _password.text
                                    ? 'Passwords do not match.'
                                    : null,
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              AppInlineNotice(
                                text: _error!,
                                tone: AppNoticeTone.error,
                              ),
                            ],
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const AppProgressIndicator(
                                      label: 'Submitting account form',
                                    )
                                  : Text(
                                      _register ? 'Create account' : 'Sign in'),
                            ),
                            const SizedBox(height: 6),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                        _register = !_register;
                                        _error = null;
                                      }),
                              child: Text(_register
                                  ? 'Use an existing account'
                                  : 'Create a new account'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = ref.read(authServiceProvider);
      if (_register) {
        await auth.register(
            email: _email.text.trim(), password: _password.text);
      } else {
        await auth.login(email: _email.text.trim(), password: _password.text);
      }
      ref.invalidate(currentUserProvider);
      ref.invalidate(targetProvider);
    } catch (error, stackTrace) {
      debugPrint('SecureWave auth failed: $error\n$stackTrace');
      if (mounted) {
        setState(() => _error = ApiError.messageFrom(error,
            fallback:
                'Authentication failed. Check your details and try again.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

enum _HomeDestination {
  connect('Connect', Icons.shield_outlined, Icons.shield_rounded),
  servers('Servers', Icons.dns_outlined, Icons.dns_rounded),
  settings('Settings', Icons.settings_outlined, Icons.settings_rounded);

  const _HomeDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  String get semanticsLabel => '$label navigation destination';
}

class _HomeView extends ConsumerStatefulWidget {
  const _HomeView({required this.isDemo});

  final bool isDemo;

  @override
  ConsumerState<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<_HomeView> {
  _HomeDestination _selected = _HomeDestination.connect;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < AppUIv1.mobileMax;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: compact ? AppUIv1.mobilePadding : AppUIv1.desktopPadding,
        title: compact
            ? const _BrandMark(compact: true)
            : Row(
                children: [
                  const _BrandMark(compact: true),
                  const Spacer(),
                  _DesktopNavigation(
                    selected: _selected,
                    onSelected: _selectDestination,
                  ),
                ],
              ),
      ),
      body: IndexedStack(
        index: _selected.index,
        children: [
          _ConnectPage(isDemo: widget.isDemo),
          const _ServersPage(),
          const _SettingsPage(),
        ],
      ),
      bottomNavigationBar: compact
          ? Semantics(
              label: 'Primary navigation',
              container: true,
              child: NavigationBar(
                key: const ValueKey('mobile-navigation'),
                selectedIndex: _selected.index,
                onDestinationSelected: (index) =>
                    _selectDestination(_HomeDestination.values[index]),
                destinations: [
                  for (final destination in _HomeDestination.values)
                    NavigationDestination(
                      icon: _NavigationSemanticIcon(
                        destination: destination,
                        selected: false,
                      ),
                      selectedIcon: _NavigationSemanticIcon(
                        destination: destination,
                        selected: true,
                      ),
                      label: destination.label,
                      tooltip: destination.semanticsLabel,
                    ),
                ],
              ),
            )
          : null,
    );
  }

  void _selectDestination(_HomeDestination destination) {
    if (_selected == destination) return;
    setState(() => _selected = destination);
  }
}

class _NavigationSemanticIcon extends StatelessWidget {
  const _NavigationSemanticIcon({
    required this.destination,
    required this.selected,
  });

  final _HomeDestination destination;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey(
        'mobile-nav-${destination.name}-${selected ? 'selected' : 'unselected'}',
      ),
      label: destination.semanticsLabel,
      selected: selected,
      child: Icon(selected ? destination.selectedIcon : destination.icon),
    );
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.selected,
    required this.onSelected,
  });

  final _HomeDestination selected;
  final ValueChanged<_HomeDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Primary navigation',
      container: true,
      child: Row(
        key: const ValueKey('desktop-navigation'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final destination in _HomeDestination.values) ...[
            if (destination != _HomeDestination.values.first)
              const SizedBox(width: 4),
            _DesktopDestination(
              destination: destination,
              selected: selected == destination,
              onPressed: () => onSelected(destination),
            ),
          ],
        ],
      ),
    );
  }
}

class _DesktopDestination extends StatelessWidget {
  const _DesktopDestination({
    required this.destination,
    required this.selected,
    required this.onPressed,
  });

  final _HomeDestination destination;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: ValueKey('desktop-nav-${destination.name}'),
      label: destination.semanticsLabel,
      button: true,
      focusable: true,
      selected: selected,
      onTap: onPressed,
      excludeSemantics: true,
      child: TextButton.icon(
        onPressed: onPressed,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(104, 44)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (selected) return AppUIv1.graphite;
            if (states.contains(WidgetState.hovered)) return AppUIv1.graphite;
            return AppUIv1.graphiteMuted;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return AppUIv1.primarySoft;
            }
            if (selected) return AppUIv1.surfaceRaised;
            if (states.contains(WidgetState.hovered)) {
              return AppUIv1.surfaceMuted;
            }
            return Colors.transparent;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return const BorderSide(color: AppUIv1.focus, width: 2);
            }
            if (selected) {
              return const BorderSide(color: AppUIv1.primary);
            }
            return BorderSide.none;
          }),
          overlayColor: WidgetStatePropertyAll(
            AppUIv1.primary.withValues(alpha: 0.12),
          ),
        ),
        icon: Icon(
          selected ? destination.selectedIcon : destination.icon,
          size: 18,
          color: selected ? AppUIv1.cyan : null,
        ),
        label: Text(destination.label),
      ),
    );
  }
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.storageKey, required this.child});

  final String storageKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < AppUIv1.mobileMax;
    final horizontalPadding =
        compact ? AppUIv1.mobilePadding : AppUIv1.desktopPadding;
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          key: PageStorageKey(storageKey),
          primary: false,
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            AppUIv1.desktopPadding,
            horizontalPadding,
            40,
          ),
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: AppUIv1.contentMaxWidth),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ConnectPage extends ConsumerWidget {
  const _ConnectPage({required this.isDemo});

  final bool isDemo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnStateProvider);
    final target = ref.watch(targetProvider);
    return _PageFrame(
      storageKey: 'connect-page',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isDemo) const _DemoBanner(),
          if (isDemo) const SizedBox(height: 16),
          _ConnectionHeader(status: vpn.status, isDemo: isDemo),
          const SizedBox(height: 18),
          _ConnectionCard(
            vpn: vpn,
            target: target,
            onConnect: () =>
                unawaited(ref.read(vpnStateProvider.notifier).connect()),
            onDisconnect: () =>
                unawaited(ref.read(vpnStateProvider.notifier).disconnect()),
          ),
          const SizedBox(height: 16),
          _DetailsRow(vpn: vpn, target: target),
          if (vpn.errorMessage != null) ...[
            const SizedBox(height: 16),
            AppInlineNotice(
              text: vpn.errorMessage!,
              tone: AppNoticeTone.error,
            ),
          ],
        ],
      ),
    );
  }
}

class _ServersPage extends ConsumerWidget {
  const _ServersPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(targetProvider);
    return _PageFrame(
      storageKey: 'servers-page',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Servers', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Your current SecureWave WireGuard target.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          target.when(
            data: (value) => AppPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.dns_outlined,
                        color: AppUIv1.cyan,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          value.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(width: 12),
                      AppStatusChip(
                        label: value.health,
                        tone: _serverHealthTone(value.health),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Divider(height: 1),
                  const SizedBox(height: 18),
                  _InformationRow(label: 'Location', value: value.location),
                  const SizedBox(height: 14),
                  const _InformationRow(
                    label: 'Protocol',
                    value: 'WireGuard',
                  ),
                ],
              ),
            ),
            loading: () => const AppStatePanel(
              title: 'Loading server',
              message: 'Retrieving the current SecureWave target.',
              tone: AppStateTone.loading,
            ),
            error: (error, _) => AppStatePanel(
              title: 'Server unavailable',
              message: ApiError.messageFrom(
                error,
                fallback: 'SecureWave could not load the current server.',
              ),
              tone: AppStateTone.error,
            ),
          ),
        ],
      ),
    );
  }

  AppStatusTone _serverHealthTone(String health) {
    return switch (health.toLowerCase()) {
      'healthy' || 'available' || 'online' => AppStatusTone.success,
      'degraded' || 'transitioning' => AppStatusTone.warning,
      'unhealthy' || 'offline' || 'error' => AppStatusTone.error,
      _ => AppStatusTone.neutral,
    };
  }
}

class _SettingsPage extends ConsumerStatefulWidget {
  const _SettingsPage();

  @override
  ConsumerState<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<_SettingsPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final session = ref.watch(authSessionProvider);
    return _PageFrame(
      storageKey: 'settings-page',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Account and session settings for this device.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Account', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 18),
                user.when(
                  data: (value) => Column(
                    children: [
                      _InformationRow(label: 'Email', value: value.email),
                      const SizedBox(height: 14),
                      _InformationRow(
                        label: 'Account status',
                        trailing: AppStatusChip(
                          label: value.isActive ? 'Active' : 'Inactive',
                          tone: value.isActive
                              ? AppStatusTone.success
                              : AppStatusTone.warning,
                        ),
                      ),
                    ],
                  ),
                  loading: () => const Align(
                    alignment: Alignment.centerLeft,
                    child: AppProgressIndicator(label: 'Loading account'),
                  ),
                  error: (error, _) => AppInlineNotice(
                    text: ApiError.messageFrom(
                      error,
                      fallback: 'SecureWave could not load your account.',
                    ),
                    tone: AppNoticeTone.error,
                  ),
                ),
                const SizedBox(height: 18),
                const Divider(height: 1),
                const SizedBox(height: 18),
                _InformationRow(
                  label: 'Device session',
                  value: session.accessToken == null
                      ? 'Signed out'
                      : 'Stored securely',
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _signOut,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppUIv1.red,
                      side: const BorderSide(color: AppUIv1.red),
                    ),
                    icon: _busy
                        ? const AppProgressIndicator(label: 'Signing out')
                        : const Icon(Icons.logout_outlined),
                    label: Text(_busy ? 'Signing out' : 'Sign out'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await ref.read(authServiceProvider).logout();
      ref.invalidate(currentUserProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({
    required this.label,
    this.value,
    this.trailing,
  }) : assert(value != null || trailing != null);

  final String label;
  final String? value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: trailing ??
              Text(
                value!,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.titleSmall,
              ),
        ),
      ],
    );
  }
}

class _ConnectionHeader extends StatelessWidget {
  const _ConnectionHeader({required this.status, required this.isDemo});

  final VpnStatus status;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    final connected = status == VpnStatus.connected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(connected ? 'Protected' : 'Private internet, one tap away',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          isDemo
              ? 'A deterministic simulated WireGuard experience.'
              : 'A real WireGuard tunnel to SecureWave Beta.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard(
      {required this.vpn,
      required this.target,
      required this.onConnect,
      required this.onDisconnect});

  final VpnState vpn;
  final AsyncValue<SecureWaveTarget> target;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final busy = vpn.status == VpnStatus.connecting ||
        vpn.status == VpnStatus.disconnecting;
    final connected = vpn.status == VpnStatus.connected;
    final statusLabel = switch (vpn.status) {
      VpnStatus.disconnected => 'Disconnected',
      VpnStatus.connecting => 'Connecting',
      VpnStatus.connected => 'Connected',
      VpnStatus.disconnecting => 'Disconnecting',
      VpnStatus.error => 'Connection error',
    };
    final targetLabel = target.maybeWhen(
      data: (value) => value.name,
      orElse: () => 'SecureWave Beta',
    );
    final actionLabel = switch (vpn.status) {
      VpnStatus.connecting => 'Connecting',
      VpnStatus.disconnecting => 'Disconnecting',
      VpnStatus.connected => 'Disconnect',
      _ => 'Connect',
    };
    return AppPanel(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppStatusChip(
                key: const ValueKey('vpn-status-chip'),
                label: statusLabel,
                tone: _vpnStatusTone(vpn.status),
              ),
              if (busy) ...[
                const Spacer(),
                AppProgressIndicator(label: statusLabel),
              ],
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 58,
            child: FilledButton.icon(
              key: const ValueKey('connection-action'),
              onPressed: busy
                  ? null
                  : connected
                      ? onDisconnect
                      : onConnect,
              style: connected
                  ? FilledButton.styleFrom(
                      backgroundColor: AppUIv1.red,
                      foregroundColor: AppUIv1.background,
                    )
                  : null,
              icon: Icon(
                connected
                    ? Icons.stop_circle_outlined
                    : Icons.power_settings_new_rounded,
              ),
              label: Text(actionLabel),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Icon(Icons.shield_outlined, size: 18),
              const SizedBox(width: 8),
              Text('WireGuard', style: Theme.of(context).textTheme.bodyMedium),
              const Spacer(),
              Flexible(
                child: Text(
                  targetLabel,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailsRow extends StatelessWidget {
  const _DetailsRow({required this.vpn, required this.target});

  final VpnState vpn;
  final AsyncValue<SecureWaveTarget> target;

  @override
  Widget build(BuildContext context) {
    final health = _Detail(
      label: 'Connection health',
      value: vpn.healthLabel,
      icon: Icons.favorite_border_rounded,
    );
    final usage = _Detail(
      label: 'Session usage',
      value: '${_formatBytes(vpn.rxBytes + vpn.txBytes)} transferred',
      icon: Icons.swap_vert_rounded,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [health, const SizedBox(height: 12), usage],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: health),
            const SizedBox(width: 12),
            Expanded(child: usage),
          ],
        );
      },
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppUIv1.primary),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleMedium)
              ])),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 26 : 34,
          height: compact ? 26 : 34,
          decoration: BoxDecoration(
            color: AppUIv1.primary,
            borderRadius: BorderRadius.circular(7),
            boxShadow: const [AppUIv1.accentGlow],
          ),
          child: Icon(
            Icons.waves_rounded,
            color: Colors.white,
            size: compact ? 17 : 22,
          ),
        ),
        const SizedBox(width: 10),
        Text('SecureWave',
            style: (compact
                    ? Theme.of(context).textTheme.titleMedium
                    : Theme.of(context).textTheme.headlineMedium)
                ?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return const AppInlineNotice(
      text: 'DEMO MODE · Simulated connection only',
      tone: AppNoticeTone.warning,
    );
  }
}

AppStatusTone _vpnStatusTone(VpnStatus status) {
  return switch (status) {
    VpnStatus.connected => AppStatusTone.success,
    VpnStatus.connecting || VpnStatus.disconnecting => AppStatusTone.warning,
    VpnStatus.error => AppStatusTone.error,
    VpnStatus.disconnected => AppStatusTone.neutral,
  };
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

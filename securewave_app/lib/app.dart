import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/constants/app_constants.dart';
import 'core/models/server_region.dart';
import 'core/models/user_plan.dart';
import 'core/models/vpn_protocol.dart';
import 'core/models/vpn_status.dart';
import 'core/services/auth_session.dart';
import 'core/state/app_state.dart';
import 'core/state/vpn_state.dart';
import 'core/utils/api_error.dart';
import 'services/auth_service.dart';
import 'services/external_links.dart';
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 900;
            final horizontalPadding = desktop ? 32.0 : 16.0;
            final verticalPadding = desktop ? 32.0 : 16.0;
            final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
            final bottomPadding = math.max(verticalPadding, keyboardInset + 16);
            return SingleChildScrollView(
              key: const ValueKey('authentication-scroll-view'),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                verticalPadding,
                horizontalPadding,
                bottomPadding,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(
                    0,
                    constraints.maxHeight - verticalPadding - bottomPadding,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: AppUIv1.maxWidth),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AuthHeader(
                          desktop: desktop,
                        ),
                        SizedBox(height: desktop ? 28 : 20),
                        _AuthenticationCard(
                          formKey: _formKey,
                          email: _email,
                          password: _password,
                          confirm: _confirm,
                          register: _register,
                          busy: _busy,
                          hidePassword: _hidePassword,
                          error: _error,
                          isDemo: config.demoMode,
                          onTogglePassword: _togglePasswordVisibility,
                          onSubmit: _submit,
                          onSwitchMode: _switchMode,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _togglePasswordVisibility() {
    if (_busy) return;
    setState(() => _hidePassword = !_hidePassword);
  }

  void _switchMode() {
    if (_busy) return;
    setState(() {
      _register = !_register;
      _error = null;
      _formKey.currentState?.reset();
    });
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
    } catch (error) {
      if (mounted) {
        setState(() => _error = _authenticationErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _AuthHeader extends StatelessWidget {
  const _AuthHeader({required this.desktop});

  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key:
          ValueKey(desktop ? 'desktop-auth-introduction' : 'mobile-auth-brand'),
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              desktop ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            const _BrandMark(),
            const SizedBox(height: 28),
            Text(
              'SecureWave Linux beta',
              textAlign: desktop ? TextAlign.center : TextAlign.left,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            Text(
              desktop
                  ? 'A focused WireGuard client for the SecureWave Linux beta.'
                  : 'WireGuard access for the SecureWave Linux beta.',
              textAlign: desktop ? TextAlign.center : TextAlign.left,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppUIv1.graphiteMuted,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthenticationCard extends StatelessWidget {
  const _AuthenticationCard({
    required this.formKey,
    required this.email,
    required this.password,
    required this.confirm,
    required this.register,
    required this.busy,
    required this.hidePassword,
    required this.error,
    required this.isDemo,
    required this.onTogglePassword,
    required this.onSubmit,
    required this.onSwitchMode,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController email;
  final TextEditingController password;
  final TextEditingController confirm;
  final bool register;
  final bool busy;
  final bool hidePassword;
  final String? error;
  final bool isDemo;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;
  final VoidCallback onSwitchMode;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      key: const ValueKey('authentication-card'),
      padding: const EdgeInsets.all(28),
      child: Form(
        key: formKey,
        child: AutofillGroup(
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  register ? 'Create your account' : 'Sign in',
                  key: const ValueKey('authentication-title'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  register
                      ? 'Create an account for the SecureWave Linux beta.'
                      : 'Use your SecureWave account to continue.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (isDemo) ...[
                  const SizedBox(height: 16),
                  const _DemoBanner(),
                ],
                const SizedBox(height: 24),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(1),
                  child: TextFormField(
                    key: const ValueKey('auth-email-field'),
                    controller: email,
                    enabled: !busy,
                    autofillHints: const [AutofillHints.email],
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'name@example.test',
                    ),
                    validator: _validateEmail,
                  ),
                ),
                const SizedBox(height: 16),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(2),
                  child: TextFormField(
                    key: const ValueKey('auth-password-field'),
                    controller: password,
                    enabled: !busy,
                    obscureText: hidePassword,
                    autofillHints: [
                      register
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    textInputAction:
                        register ? TextInputAction.next : TextInputAction.done,
                    onFieldSubmitted:
                        register || busy ? null : (_) => onSubmit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        key: const ValueKey('auth-password-visibility'),
                        tooltip:
                            hidePassword ? 'Show password' : 'Hide password',
                        onPressed: busy ? null : onTogglePassword,
                        icon: Icon(
                          hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: _validatePassword,
                  ),
                ),
                if (register) ...[
                  const SizedBox(height: 16),
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(3),
                    child: TextFormField(
                      key: const ValueKey('auth-confirm-field'),
                      controller: confirm,
                      enabled: !busy,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: busy ? null : (_) => onSubmit(),
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Confirm your password.';
                        }
                        if (value != password.text) {
                          return 'Passwords do not match.';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 16),
                  AppInlineNotice(
                    key: const ValueKey('authentication-error'),
                    text: error!,
                    tone: AppNoticeTone.error,
                  ),
                ],
                const SizedBox(height: 22),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(4),
                  child: FilledButton(
                    key: const ValueKey('authentication-primary-action'),
                    onPressed: busy ? null : onSubmit,
                    child: busy
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppProgressIndicator(
                                label: register
                                    ? 'Creating account'
                                    : 'Signing in',
                              ),
                              const SizedBox(width: 10),
                              Text(
                                register ? 'Creating account' : 'Signing in',
                              ),
                            ],
                          )
                        : Text(register ? 'Create account' : 'Sign in'),
                  ),
                ),
                const SizedBox(height: 10),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(5),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        register
                            ? 'Already have an account?'
                            : 'New to SecureWave?',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      TextButton(
                        key: const ValueKey('authentication-mode-switch'),
                        onPressed: busy ? null : onSwitchMode,
                        child: Text(register ? 'Sign in' : 'Create an account'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email.';
    if (!email.contains('@')) return 'Enter a valid email.';
    return null;
  }

  static String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter your password.';
    if (value.length < 8) return 'Use at least 8 characters.';
    return null;
  }
}

String _authenticationErrorMessage(Object error) {
  const fallback = 'Authentication failed. Check your details and try again.';
  final mapped = ApiError.messageFrom(error, fallback: fallback).trim();
  if (mapped.isEmpty ||
      mapped.startsWith('HTTP ') ||
      mapped.contains('DioException') ||
      mapped.contains('access token')) {
    return fallback;
  }
  return mapped;
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
    final content = IndexedStack(
      index: _selected.index,
      children: [
        _ConnectPage(
          isDemo: widget.isDemo,
          onChooseServer: () => _selectDestination(_HomeDestination.servers),
        ),
        const _ServersPage(),
        const _SettingsPage(),
      ],
    );

    return Scaffold(
      appBar: compact
          ? AppBar(
              titleSpacing: AppUIv1.mobilePadding,
              title: const _BrandMark(compact: true),
            )
          : null,
      body: compact
          ? content
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DesktopRail(
                  selected: _selected,
                  isDemo: widget.isDemo,
                  onSelected: _selectDestination,
                ),
                Expanded(child: content),
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

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({
    required this.selected,
    required this.isDemo,
    required this.onSelected,
  });

  final _HomeDestination selected;
  final bool isDemo;
  final ValueChanged<_HomeDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      decoration: const BoxDecoration(
        color: AppUIv1.surface,
        border: Border(right: BorderSide(color: AppUIv1.line)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _BrandMark(compact: true),
          const SizedBox(height: 36),
          Text(
            'Workspace',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          _DesktopNavigation(
            selected: selected,
            onSelected: onSelected,
            vertical: true,
          ),
          const Spacer(),
          if (isDemo) const _DemoBanner(),
          if (isDemo) const SizedBox(height: 12),
          Text(
            'SecureWave Linux beta',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
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
    this.vertical = false,
  });

  final _HomeDestination selected;
  final ValueChanged<_HomeDestination> onSelected;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Primary navigation',
      container: true,
      child: Flex(
        direction: vertical ? Axis.vertical : Axis.horizontal,
        key: const ValueKey('desktop-navigation'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final destination in _HomeDestination.values) ...[
            if (destination != _HomeDestination.values.first)
              SizedBox(width: vertical ? 0 : 4, height: vertical ? 4 : 0),
            _DesktopDestination(
              destination: destination,
              selected: selected == destination,
              vertical: vertical,
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
    this.vertical = false,
  });

  final _HomeDestination destination;
  final bool selected;
  final VoidCallback onPressed;
  final bool vertical;

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
          minimumSize: WidgetStatePropertyAll(
            Size(vertical ? double.infinity : 104, 44),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14),
          ),
          alignment:
              vertical ? AlignmentDirectional.centerStart : Alignment.center,
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
  const _PageFrame({
    required this.storageKey,
    required this.child,
    this.maxWidth = AppUIv1.contentMaxWidth,
  });

  final String storageKey;
  final Widget child;
  final double maxWidth;

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
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ConnectPage extends ConsumerWidget {
  const _ConnectPage({
    required this.isDemo,
    required this.onChooseServer,
  });

  final bool isDemo;
  final VoidCallback onChooseServer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnStateProvider);
    final servers = ref.watch(serversProvider);
    final plan = ref.watch(userPlanProvider);
    final availability = _wireGuardAvailability(
      servers: servers,
      selectedServerId: vpn.selectedServerId,
    );
    final selectedServer = _selectedServer(
      servers.valueOrNull ?? const <ServerRegion>[],
      vpn.selectedServerId,
    );
    final locationLabel = vpn.selectedServerId == null
        ? 'Auto-select'
        : selectedServer?.location ??
            selectedServer?.name ??
            'Selected location unavailable';
    return _PageFrame(
      storageKey: 'connect-page',
      maxWidth: 1040,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hero = _ConnectionDashboardHero(
            vpn: vpn,
            availability: availability,
            locationLabel: locationLabel,
            onConnect: () =>
                unawaited(ref.read(vpnStateProvider.notifier).connect()),
            onDisconnect: () =>
                unawaited(ref.read(vpnStateProvider.notifier).disconnect()),
            onDiagnostics: () => _showDiagnostics(context),
            onChooseServer: onChooseServer,
          );
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SessionSummary(
                vpn: vpn,
                locationLabel: locationLabel,
              ),
              const SizedBox(height: 16),
              _PlanPanel(plan: plan),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isDemo) const _DemoBanner(),
              if (isDemo) const SizedBox(height: 16),
              Text(
                'Connection',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Control the current SecureWave WireGuard beta connection.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              if (constraints.maxWidth >= 820)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: hero),
                    const SizedBox(width: 16),
                    Expanded(flex: 5, child: summary),
                  ],
                )
              else ...[
                hero,
                const SizedBox(height: 16),
                summary,
              ],
              if (vpn.errorMessage != null) ...[
                const SizedBox(height: 16),
                AppInlineNotice(
                  key: const ValueKey('connection-error'),
                  text: vpn.errorMessage!,
                  tone: AppNoticeTone.error,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ServersPage extends ConsumerStatefulWidget {
  const _ServersPage();

  @override
  ConsumerState<_ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends ConsumerState<_ServersPage> {
  bool _staleSelectionRecovered = false;
  bool _recoveryScheduled = false;

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(serversProvider);
    final vpn = ref.watch(vpnStateProvider);
    final selectionLocked = vpn.status == VpnStatus.connected ||
        vpn.status == VpnStatus.connecting ||
        vpn.status == VpnStatus.disconnecting;
    return _PageFrame(
      storageKey: 'servers-page',
      maxWidth: 900,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Servers', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'The Linux beta currently uses a limited, verified location catalog.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          if (selectionLocked) ...[
            const AppInlineNotice(
              text: 'Disconnect before changing the selected location.',
              tone: AppNoticeTone.info,
            ),
            const SizedBox(height: 14),
          ],
          servers.when(
            data: (items) => _buildCatalog(
              context,
              items,
              vpn,
              selectionLocked: selectionLocked,
            ),
            loading: () => const AppStatePanel(
              key: ValueKey('servers-loading'),
              title: 'Loading locations',
              message: 'Retrieving the current SecureWave beta catalog.',
              tone: AppStateTone.loading,
            ),
            error: (error, _) => AppStatePanel(
              key: const ValueKey('servers-error'),
              title: 'Locations unavailable',
              message: ApiError.messageFrom(
                error,
                fallback: 'SecureWave could not load the location catalog.',
              ),
              tone: AppStateTone.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalog(
    BuildContext context,
    List<ServerRegion> items,
    VpnState vpn, {
    required bool selectionLocked,
  }) {
    if (items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppStatePanel(
            key: ValueKey('servers-empty'),
            title: 'No locations available',
            message:
                'Auto-select will remain active until the catalog returns.',
            tone: AppStateTone.empty,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => ref.invalidate(serversProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry catalog'),
            ),
          ),
        ],
      );
    }

    final ids = items.map((server) => server.id).where((id) => id.isNotEmpty);
    final stale = vpn.selectedServerId != null &&
        !items.any((server) => server.id == vpn.selectedServerId);
    if (stale && !_recoveryScheduled) {
      _recoveryScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final recovered = await ref
            .read(vpnStateProvider.notifier)
            .recoverStaleServerSelection(ids);
        if (mounted) {
          setState(() {
            _recoveryScheduled = false;
            _staleSelectionRecovered = _staleSelectionRecovered || recovered;
          });
        }
      });
    }

    final anyConnectable = items.any((server) => server.isWireGuardConnectable);
    return Column(
      key: const ValueKey('servers-catalog'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stale || _staleSelectionRecovered) ...[
          const AppInlineNotice(
            key: ValueKey('stale-server-notice'),
            text:
                'The previous location is no longer in the catalog. Auto-select was restored.',
            tone: AppNoticeTone.warning,
          ),
          const SizedBox(height: 14),
        ],
        _ServerSelectionCard(
          key: const ValueKey('server-auto-select'),
          title: 'Auto-select',
          subtitle: anyConnectable
              ? 'Use the available WireGuard beta location.'
              : 'Waiting for verified WireGuard location evidence.',
          icon: Icons.near_me_outlined,
          selected: vpn.selectedServerId == null,
          enabled: anyConnectable && !selectionLocked,
          onTap: () => unawaited(
            ref.read(vpnStateProvider.notifier).selectServer(null),
          ),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < items.length; index++) ...[
          _ServerSelectionCard(
            key: ValueKey('server-location-$index'),
            title: items[index].name,
            subtitle: items[index].location,
            icon: Icons.location_on_outlined,
            selected: vpn.selectedServerId == items[index].id,
            enabled: items[index].id.isNotEmpty &&
                items[index].isWireGuardConnectable &&
                !selectionLocked,
            server: items[index],
            onTap: () => unawaited(
              ref.read(vpnStateProvider.notifier).selectServer(items[index].id),
            ),
          ),
          if (index < items.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ServerSelectionCard extends StatelessWidget {
  const _ServerSelectionCard({
    required this.title,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
    super.key,
    this.subtitle,
    this.server,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final ServerRegion? server;

  @override
  Widget build(BuildContext context) {
    final details = server == null ? const <Widget>[] : _serverDetails(server!);
    return Semantics(
      label: '$title server selection',
      button: true,
      selected: selected,
      enabled: enabled,
      child: Material(
        color: selected ? AppUIv1.primarySoft : AppUIv1.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppUIv1.radius),
          side: BorderSide(
            color: selected ? AppUIv1.primary : AppUIv1.line,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          focusColor: AppUIv1.focus.withValues(alpha: 0.18),
          hoverColor: AppUIv1.primary.withValues(alpha: 0.10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    selected ? Icons.check_circle_rounded : icon,
                    color: selected
                        ? AppUIv1.cyan
                        : enabled
                            ? AppUIv1.graphiteMuted
                            : AppUIv1.disabled,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              selected ? 'Selected' : 'Not selected',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ],
                        ),
                        if (subtitle != null &&
                            subtitle!.trim().isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            subtitle!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                        if (details.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, runSpacing: 8, children: details),
                        ],
                        if (!enabled && server != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            server!.isUnavailable
                                ? 'This location is currently unavailable.'
                                : 'WireGuard support is not verified for this location.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppUIv1.amber),
                          ),
                        ],
                      ],
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

  List<Widget> _serverDetails(ServerRegion value) {
    final details = <Widget>[];
    void add(String label, {AppStatusTone tone = AppStatusTone.neutral}) {
      details.add(
        AppStatusChip(label: label, tone: tone),
      );
    }

    if (value.city != null) add(value.city!);
    if (value.country != null) add(value.country!);
    if (value.latencyMs != null) add('${value.latencyMs} ms');
    if (value.loadPercent != null) {
      add('${value.loadPercent!.round()}% load');
    }
    if (value.health != null) {
      add(
        value.health!,
        tone: _serverHealthTone(value.health!),
      );
    }
    if (value.hasProtocolEvidenceFor(VpnProtocol.wireGuard)) {
      add('WireGuard', tone: AppStatusTone.info);
    }
    return details;
  }
}

AppStatusTone _serverHealthTone(String health) {
  return switch (health.toLowerCase()) {
    'healthy' || 'available' || 'online' || 'up' => AppStatusTone.success,
    'degraded' || 'transitioning' => AppStatusTone.warning,
    'unhealthy' || 'offline' || 'unavailable' || 'error' => AppStatusTone.error,
    _ => AppStatusTone.neutral,
  };
}

class _SettingsPage extends ConsumerStatefulWidget {
  const _SettingsPage();

  @override
  ConsumerState<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<_SettingsPage> {
  bool _busy = false;
  String? _signOutError;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final plan = ref.watch(userPlanProvider);
    final vpn = ref.watch(vpnStateProvider);
    final vpnBusy = vpn.status == VpnStatus.connecting ||
        vpn.status == VpnStatus.disconnecting;
    return _PageFrame(
      storageKey: 'settings-page',
      maxWidth: 900,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Manage your account, data allowance, and local app actions.',
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
                      _InformationRow(
                        label: 'Signed-in email',
                        value:
                            value.email.isEmpty ? 'Not provided' : value.email,
                      ),
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
                      if (value.emailVerified != null) ...[
                        const SizedBox(height: 14),
                        _InformationRow(
                          label: 'Email status',
                          trailing: AppStatusChip(
                            label: value.emailVerified!
                                ? 'Verified'
                                : 'Unverified',
                            tone: value.emailVerified!
                                ? AppStatusTone.success
                                : AppStatusTone.warning,
                          ),
                        ),
                      ],
                      if (value.subscriptionStatus != null) ...[
                        const SizedBox(height: 14),
                        _InformationRow(
                          label: 'Subscription',
                          value: value.subscriptionStatus!,
                        ),
                      ],
                    ],
                  ),
                  loading: () => const AppStatePanel(
                    key: ValueKey('settings-account-loading'),
                    title: 'Loading account',
                    message: 'Retrieving your signed-in account details.',
                    tone: AppStateTone.loading,
                  ),
                  error: (error, _) => AppStatePanel(
                    key: const ValueKey('settings-account-error'),
                    title: 'Account unavailable',
                    message: ApiError.messageFrom(
                      error,
                      fallback: 'SecureWave could not load your account.',
                    ),
                    tone: AppStateTone.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _PlanPanel(plan: plan),
          const SizedBox(height: 16),
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Actions', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  key: const ValueKey('settings-diagnostics-action'),
                  onPressed: () => _showDiagnostics(context),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Open diagnostics'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const ValueKey('account-portal-action'),
                  onPressed: _openAccountPortal,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open account portal'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const ValueKey('sign-out-action'),
                  onPressed: _busy || vpnBusy ? null : _signOut,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppUIv1.red,
                    side: const BorderSide(color: AppUIv1.red),
                  ),
                  icon: _busy
                      ? const AppProgressIndicator(label: 'Signing out')
                      : const Icon(Icons.logout_outlined),
                  label: Text(_busy ? 'Signing out' : 'Sign out'),
                ),
                if (vpnBusy) ...[
                  const SizedBox(height: 12),
                  const AppInlineNotice(
                    text:
                        'Wait for the current VPN transition before signing out.',
                    tone: AppNoticeTone.warning,
                  ),
                ],
                if (_signOutError != null) ...[
                  const SizedBox(height: 12),
                  AppInlineNotice(
                    text: _signOutError!,
                    tone: AppNoticeTone.error,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openAccountPortal() {
    unawaited(
      ref.read(externalLinksProvider).openUrl(AppConstants.portalUrlFallback),
    );
  }

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _signOutError = null;
    });
    try {
      final notifier = ref.read(vpnStateProvider.notifier);
      final vpn = ref.read(vpnStateProvider);
      if (vpn.status != VpnStatus.disconnected) {
        await notifier.disconnect();
      }
      await notifier.selectServer(null);
      await ref.read(authServiceProvider).logout();
      ref.invalidate(currentUserProvider);
      ref.invalidate(userPlanProvider);
      ref.invalidate(serversProvider);
      ref.invalidate(targetProvider);
    } catch (error) {
      if (mounted && ref.read(authSessionProvider).isAuthenticated) {
        setState(() {
          _signOutError = ApiError.messageFrom(
            error,
            fallback: 'SecureWave could not finish signing out.',
          );
        });
      }
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

class _ConnectionDashboardHero extends StatelessWidget {
  const _ConnectionDashboardHero({
    required this.vpn,
    required this.availability,
    required this.locationLabel,
    required this.onConnect,
    required this.onDisconnect,
    required this.onDiagnostics,
    required this.onChooseServer,
  });

  final VpnState vpn;
  final _ConnectionAvailability availability;
  final String locationLabel;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onDiagnostics;
  final VoidCallback onChooseServer;

  @override
  Widget build(BuildContext context) {
    final busy = vpn.status == VpnStatus.connecting ||
        vpn.status == VpnStatus.disconnecting;
    final connected = vpn.status == VpnStatus.connected;
    final statusLabel = _vpnStatusLabel(vpn.status);
    final actionLabel = switch (vpn.status) {
      VpnStatus.connecting => 'Connecting',
      VpnStatus.disconnecting => 'Disconnecting',
      VpnStatus.connected => 'Disconnect',
      _ => 'Connect',
    };
    final action = busy || (!connected && !availability.canConnect)
        ? null
        : connected
            ? onDisconnect
            : onConnect;

    return AppPanel(
      key: const ValueKey('connection-dashboard-hero'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: AppStatusChip(
              key: const ValueKey('vpn-status-chip'),
              label: statusLabel,
              tone: _vpnStatusTone(vpn.status),
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: Semantics(
              label: '$actionLabel VPN connection',
              button: true,
              enabled: action != null,
              excludeSemantics: true,
              child: _ConnectionOrb(
                status: vpn.status,
                busy: busy,
                connected: connected,
                actionLabel: actionLabel,
                onPressed: action,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            _vpnStatusDescription(vpn.status),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 18),
          _InformationRow(label: 'Location', value: locationLabel),
          const SizedBox(height: 12),
          const _InformationRow(label: 'Protocol', value: 'WireGuard'),
          if (!availability.canConnect && !connected) ...[
            const SizedBox(height: 16),
            AppInlineNotice(
              key: const ValueKey('connection-unavailable'),
              text: availability.message,
              tone: availability.loading
                  ? AppNoticeTone.info
                  : AppNoticeTone.warning,
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('choose-location-action'),
                onPressed: onChooseServer,
                icon: const Icon(Icons.location_on_outlined),
                label: const Text('Choose location'),
              ),
              TextButton.icon(
                key: const ValueKey('diagnostics-action'),
                onPressed: onDiagnostics,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Diagnostics'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectionOrb extends StatelessWidget {
  const _ConnectionOrb({
    required this.status,
    required this.busy,
    required this.connected,
    required this.actionLabel,
    required this.onPressed,
  });

  final VpnStatus status;
  final bool busy;
  final bool connected;
  final String actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final ringColor = busy
        ? AppUIv1.amber
        : connected
            ? AppUIv1.success
            : status == VpnStatus.error
                ? AppUIv1.red
                : AppUIv1.primary;
    return AnimatedContainer(
      duration:
          reducedMotion ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor.withValues(alpha: 0.6), width: 1),
        boxShadow: [
          BoxShadow(
            color: ringColor.withValues(alpha: 0.12),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: SizedBox.square(
        dimension: 168,
        child: FilledButton(
          key: const ValueKey('connection-action'),
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            backgroundColor: _powerButtonColor(status),
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppUIv1.surfaceRaised,
            disabledForegroundColor: AppUIv1.graphiteSubtle,
            side: BorderSide(
              color: busy ? AppUIv1.amber : AppUIv1.lineStrong,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                const SizedBox.square(
                  dimension: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppUIv1.amber,
                  ),
                )
              else
                Icon(
                  connected
                      ? Icons.power_settings_new_rounded
                      : status == VpnStatus.error
                          ? Icons.refresh_rounded
                          : Icons.power_settings_new_rounded,
                  size: 36,
                ),
              const SizedBox(height: 10),
              Text(actionLabel),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionSummary extends StatelessWidget {
  const _SessionSummary({
    required this.vpn,
    required this.locationLabel,
  });

  final VpnState vpn;
  final String locationLabel;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      key: const ValueKey('session-summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Session', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 18),
          _InformationRow(label: 'Server', value: locationLabel),
          const SizedBox(height: 12),
          const _InformationRow(label: 'Protocol', value: 'WireGuard'),
          const SizedBox(height: 12),
          _InformationRow(
            label: 'State',
            value: _vpnStatusLabel(vpn.status),
          ),
          const SizedBox(height: 12),
          _InformationRow(label: 'Runtime', value: vpn.healthLabel),
        ],
      ),
    );
  }
}

class _PlanPanel extends StatelessWidget {
  const _PlanPanel({required this.plan});

  final AsyncValue<UserPlan> plan;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      key: const ValueKey('data-allowance-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Data allowance', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 18),
          plan.when(
            data: (value) => _UsageSummary(plan: value),
            loading: () => const AppStatePanel(
              title: 'Loading allowance',
              message: 'Retrieving your current plan and usage.',
              tone: AppStateTone.loading,
            ),
            error: (error, _) => AppStatePanel(
              title: 'Allowance unavailable',
              message: ApiError.messageFrom(
                error,
                fallback: 'SecureWave could not load your data allowance.',
              ),
              tone: AppStateTone.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageSummary extends StatelessWidget {
  const _UsageSummary({required this.plan});

  final UserPlan plan;

  @override
  Widget build(BuildContext context) {
    final progress = plan.usagePercent.clamp(0.0, 1.0).toDouble();
    final cap = plan.safeDataCapGb;
    final used = plan.safeUsedGb;
    final remaining = plan.remainingGb;
    final allowanceText = plan.isUnlimited
        ? 'Unlimited data'
        : cap == 0
            ? 'No data allowance'
            : '${_formatGb(remaining)} GB remaining of ${_formatGb(cap)} GB';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                plan.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            AppStatusChip(
              label: plan.isPremium ? 'Premium' : 'Free',
              tone: plan.isPremium
                  ? AppStatusTone.success
                  : AppStatusTone.neutral,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          allowanceText,
          key: const ValueKey('allowance-remaining'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 10),
        Semantics(
          label: plan.isUnlimited
              ? 'Unlimited data allowance'
              : 'Data allowance ${(progress * 100).round()} percent used',
          child: LinearProgressIndicator(
            key: const ValueKey('allowance-progress'),
            value: plan.isUnlimited ? null : progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            color: progress >= 1 ? AppUIv1.amber : AppUIv1.primary,
            backgroundColor: AppUIv1.surfaceMuted,
          ),
        ),
        const SizedBox(height: 14),
        _InformationRow(label: 'Used', value: '${_formatGb(used)} GB'),
        const SizedBox(height: 10),
        _InformationRow(
          label: 'Cap',
          value: plan.isUnlimited ? 'Unlimited' : '${_formatGb(cap)} GB',
        ),
      ],
    );
  }
}

class _ConnectionAvailability {
  const _ConnectionAvailability({
    required this.canConnect,
    required this.message,
    this.loading = false,
  });

  final bool canConnect;
  final String message;
  final bool loading;
}

_ConnectionAvailability _wireGuardAvailability({
  required AsyncValue<List<ServerRegion>> servers,
  required String? selectedServerId,
}) {
  return servers.when(
    loading: () => const _ConnectionAvailability(
      canConnect: false,
      loading: true,
      message: 'Checking WireGuard location availability.',
    ),
    error: (error, _) => _ConnectionAvailability(
      canConnect: false,
      message: ApiError.messageFrom(
        error,
        fallback: 'WireGuard location availability could not be verified.',
      ),
    ),
    data: (items) {
      if (selectedServerId != null) {
        final selected = _selectedServer(items, selectedServerId);
        if (selected == null) {
          return const _ConnectionAvailability(
            canConnect: false,
            message: 'The selected location is no longer available.',
          );
        }
        if (!selected.isWireGuardConnectable) {
          return const _ConnectionAvailability(
            canConnect: false,
            message: 'WireGuard is unavailable for the selected location.',
          );
        }
        return const _ConnectionAvailability(
          canConnect: true,
          message: '',
        );
      }
      if (items.any((server) => server.isWireGuardConnectable)) {
        return const _ConnectionAvailability(
          canConnect: true,
          message: '',
        );
      }
      return const _ConnectionAvailability(
        canConnect: false,
        message: 'No location has verified WireGuard availability.',
      );
    },
  );
}

ServerRegion? _selectedServer(
  List<ServerRegion> servers,
  String? selectedServerId,
) {
  if (selectedServerId == null) return null;
  for (final server in servers) {
    if (server.id == selectedServerId) return server;
  }
  return null;
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

String _vpnStatusLabel(VpnStatus status) => switch (status) {
      VpnStatus.disconnected => 'Disconnected',
      VpnStatus.connecting => 'Connecting',
      VpnStatus.connected => 'Connected',
      VpnStatus.disconnecting => 'Disconnecting',
      VpnStatus.error => 'Connection error',
    };

String _vpnStatusDescription(VpnStatus status) => switch (status) {
      VpnStatus.disconnected => 'The VPN tunnel is not active.',
      VpnStatus.connecting => 'SecureWave is starting the WireGuard tunnel.',
      VpnStatus.connected => 'The WireGuard runtime reports connected.',
      VpnStatus.disconnecting => 'SecureWave is stopping the tunnel.',
      VpnStatus.error => 'The connection needs attention before retrying.',
    };

Color _powerButtonColor(VpnStatus status) => switch (status) {
      VpnStatus.connected => AppUIv1.red,
      VpnStatus.connecting || VpnStatus.disconnecting => AppUIv1.amberSoft,
      VpnStatus.error => AppUIv1.redSoft,
      VpnStatus.disconnected => AppUIv1.primary,
    };

String _formatGb(double value) {
  final safe = value.isFinite && value > 0 ? value : 0;
  final rounded = safe.roundToDouble();
  return safe == rounded ? rounded.toStringAsFixed(0) : safe.toStringAsFixed(1);
}

void _showDiagnostics(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const SafeArea(child: _DiagnosticsView()),
  );
}

class _DiagnosticsView extends ConsumerWidget {
  const _DiagnosticsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnStateProvider);
    final config = ref.watch(appConfigProvider);
    final service = ref.watch(vpnServiceProvider);
    final servers = ref.watch(serversProvider);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Diagnostics', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 18),
            _InformationRow(
              label: 'VPN state',
              value: _vpnStatusLabel(vpn.status),
            ),
            const SizedBox(height: 12),
            const _InformationRow(label: 'Protocol', value: 'WireGuard'),
            const SizedBox(height: 12),
            _InformationRow(
              label: 'Device',
              value: _devicePlatformLabel(defaultTargetPlatform),
            ),
            const SizedBox(height: 12),
            _InformationRow(
              label: 'VPN helper',
              value: service.isAvailable ? 'Available' : 'Not confirmed',
            ),
            const SizedBox(height: 12),
            _InformationRow(label: 'API target', value: config.apiBaseUrl),
            const SizedBox(height: 12),
            _InformationRow(
              label: 'Demo mode',
              value: config.demoMode ? 'Active — simulated only' : 'Off',
            ),
            const SizedBox(height: 12),
            _InformationRow(
              label: 'Location catalog',
              value: servers.when(
                data: (items) => items.isEmpty ? 'Empty' : 'Loaded',
                loading: () => 'Loading',
                error: (_, __) => 'Unavailable',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _devicePlatformLabel(TargetPlatform platform) => switch (platform) {
      TargetPlatform.linux => 'Linux desktop',
      TargetPlatform.android => 'Android device',
      TargetPlatform.iOS => 'iOS device',
      TargetPlatform.macOS => 'macOS desktop',
      TargetPlatform.windows => 'Windows desktop',
      TargetPlatform.fuchsia => 'Fuchsia device',
    };

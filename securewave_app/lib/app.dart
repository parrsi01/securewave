import 'dart:async';
import 'dart:math' as math;

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
                    child: desktop
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Expanded(child: _AuthIntroduction()),
                              const SizedBox(width: 56),
                              SizedBox(
                                width: 440,
                                child: _AuthenticationCard(
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
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Align(
                                key: ValueKey('mobile-auth-brand'),
                                alignment: Alignment.centerLeft,
                                child: _BrandMark(compact: true),
                              ),
                              const SizedBox(height: 20),
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

class _AuthIntroduction extends StatelessWidget {
  const _AuthIntroduction();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('desktop-auth-introduction'),
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _BrandMark(),
            const SizedBox(height: 40),
            Text(
              'SecureWave Linux beta',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Authenticated WireGuard connection controls for Ubuntu 24.04 ARM64.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppUIv1.graphiteMuted,
                  ),
            ),
            const SizedBox(height: 28),
            const _AuthFact(
              icon: Icons.shield_outlined,
              text: 'Connect to the SecureWave beta target.',
            ),
            const SizedBox(height: 16),
            const _AuthFact(
              icon: Icons.dns_outlined,
              text: 'View the current WireGuard server target.',
            ),
            const SizedBox(height: 16),
            const _AuthFact(
              icon: Icons.lock_outline_rounded,
              text: 'Store the signed-in session with secure device storage.',
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthFact extends StatelessWidget {
  const _AuthFact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppUIv1.cyan, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
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

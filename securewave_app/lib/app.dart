import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/bootstrap/boot_controller.dart';
import 'core/config/app_config.dart';
import 'core/constants/app_constants.dart';
import 'core/logging/app_logger.dart';
import 'core/models/server_region.dart';
import 'core/models/user_account.dart';
import 'core/models/user_plan.dart';
import 'core/models/vpn_protocol.dart';
import 'core/models/vpn_status.dart';
import 'core/services/auth_session.dart';
import 'core/services/secure_storage.dart';
import 'core/services/vpn_service.dart';
import 'core/state/app_state.dart';
import 'core/state/vpn_state.dart';
import 'core/utils/api_error.dart';
import 'services/auth_service.dart';
import 'services/external_links.dart';
import 'ui/sw_theme.dart';
import 'ui/sw_widgets.dart';

class SecureWaveApp extends ConsumerStatefulWidget {
  const SecureWaveApp({super.key});

  @override
  ConsumerState<SecureWaveApp> createState() => _SecureWaveAppState();
}

class _SecureWaveAppState extends ConsumerState<SecureWaveApp> {
  late final AppLifecycleObserver _observer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _observer = AppLifecycleObserver(onStateChange: _handleLifecycle);
    WidgetsBinding.instance.addObserver(_observer);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork = !results.contains(ConnectivityResult.none);
      unawaited(ref
          .read(vpnStateProvider.notifier)
          .handleConnectivityChange(hasNetwork: hasNetwork));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_observer);
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _handleLifecycle(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      final config = await AppConfig.load();
      if (!mounted) return;
      ref.read(appConfigProvider.notifier).state = config;
      ref.read(vpnStateProvider.notifier).resumeRateUpdates();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      ref.read(vpnStateProvider.notifier).pauseRateUpdates();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SecureWave',
      debugShowCheckedModeBanner: false,
      theme: SwTheme.light,
      home: const _AppRoot(),
    );
  }
}

class _AppRoot extends ConsumerWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(bootControllerProvider).state;
    final session = ref.watch(authSessionProvider);

    if (boot.status == BootStatus.initializing || !session.isInitialized) {
      return _BootView(message: boot.errorMessage);
    }

    if (!session.isAuthenticated) {
      return const _AuthScreen();
    }

    return const _MainShell();
  }
}

/// ---------------------------------------------------------------------------
/// Authentication
/// ---------------------------------------------------------------------------

class _AuthScreen extends ConsumerStatefulWidget {
  const _AuthScreen();

  @override
  ConsumerState<_AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<_AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;
  bool _autoLoginStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _autoLoginStarted) return;
      final config = ref.read(appConfigProvider);
      if (!config.autoLoginForTesting) return;
      _autoLoginStarted = true;
      final random = Random.secure();
      final suffix =
          List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join();
      final email =
          'securewave.qa.${DateTime.now().millisecondsSinceEpoch}.$suffix@gmail.com';
      final password = 'SwTest${random.nextInt(900000) + 100000}!A1';
      setState(() {
        _register = true;
        _email.text = email;
        _password.text = password;
        _confirm.text = password;
      });
      unawaited(_submit());
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showBrandPanel = width >= 900;

    return Scaffold(
      backgroundColor: SwColors.surface,
      body: SafeArea(
        child: Row(
          children: [
            if (showBrandPanel) const _AuthBrandPanel(),
            Expanded(child: _buildForm(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final autoLogin = ref.watch(appConfigProvider).autoLoginForTesting;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: SwSpacing.md,
          vertical: SwSpacing.lg,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwSegmentedControl(
                    segments: const ['Log in', 'Create account'],
                    index: _register ? 1 : 0,
                    onChanged: _busy
                        ? null
                        : (next) {
                            setState(() {
                              _register = next == 1;
                              _error = null;
                            });
                          },
                  ),
                  const SizedBox(height: SwSpacing.md),
                  Text(
                    _register ? 'Create your account' : 'Welcome back',
                    style: SwType.title,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _register
                        ? 'A SecureWave account keeps your tunnel and usage in sync.'
                        : 'Sign in to manage your secure session.',
                    style: SwType.body,
                  ),
                  if (autoLogin) ...[
                    const SizedBox(height: SwSpacing.sm),
                    const SwNotice(
                      title: 'Development test mode',
                      message:
                          'Generating a fresh account and signing in automatically.',
                    ),
                  ],
                  const SizedBox(height: 18),
                  TextFormField(
                    controller: _email,
                    autofillHints: const [
                      AutofillHints.username,
                      AutofillHints.email,
                    ],
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    style: SwType.body.copyWith(color: SwColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter your email.';
                      }
                      if (!value.contains('@')) {
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
                    textInputAction:
                        _register ? TextInputAction.next : TextInputAction.done,
                    style: SwType.body.copyWith(color: SwColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        tooltip:
                            _hidePassword ? 'Show password' : 'Hide password',
                        color: SwColors.textSecondary,
                        icon: Icon(
                          _hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() => _hidePassword = !_hidePassword);
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Enter your password.';
                      }
                      if (value.length < 8) {
                        return 'Use at least 8 characters.';
                      }
                      if (!RegExp(r'[A-Za-z]').hasMatch(value) ||
                          !RegExp(r'[0-9]').hasMatch(value) ||
                          !RegExp(r'[^A-Za-z0-9]').hasMatch(value)) {
                        return 'Use letters, numbers, and a special character.';
                      }
                      return null;
                    },
                  ),
                  if (_register) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _confirm,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      style: SwType.body.copyWith(color: SwColors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Confirm your password.';
                        }
                        if (value != _password.text) {
                          return 'Passwords do not match.';
                        }
                        return null;
                      },
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: SwSpacing.sm),
                    SwNotice(
                      title: 'We could not continue',
                      message: _error,
                      tone: SwNoticeTone.error,
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: SwColors.onPrimary,
                            ),
                          )
                        : Text(_register ? 'Create account' : 'Log in'),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Secured with WireGuard · Linux Beta',
                    textAlign: TextAlign.center,
                    style: SwType.footnote,
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
          email: _email.text.trim(),
          password: _password.text.trim(),
        );
      } else {
        await auth.login(
          email: _email.text.trim(),
          password: _password.text.trim(),
        );
      }
      ref.invalidate(currentUserProvider);
      ref.invalidate(userPlanProvider);
      ref.invalidate(serversProvider);
    } catch (error, stackTrace) {
      AppLogger.error('Auth form failed', error: error, stackTrace: stackTrace);
      setState(() {
        _error = ApiError.messageFrom(
          error,
          fallback: _register
              ? 'We could not create your account. Please try again.'
              : 'We could not sign you in. Check your details and try again.',
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _AuthBrandPanel extends StatelessWidget {
  const _AuthBrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: SwLayout.authPanelWidth,
      color: SwColors.primarySoft,
      padding:
          const EdgeInsets.symmetric(horizontal: SwSpacing.xl, vertical: 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SwLogo(size: 38),
              const SizedBox(width: 12),
              Text('SecureWave', style: SwType.wordmark.copyWith(fontSize: 20)),
            ],
          ),
          const Spacer(),
          const Text('Private\nconnection.\nOne click.',
              style: SwType.headline),
          const SizedBox(height: 14),
          const Text(
            'A single encrypted WireGuard tunnel for your Linux desktop.',
            style: SwType.body,
          ),
          const SizedBox(height: SwSpacing.lg),
          // Only claims the client can actually evidence. Do not add a
          // "no logs" claim here: the app posts connect/disconnect events to
          // the backend (ApiClient.notifyVpnConnected) and the account is
          // metered, so that claim would be false.
          const SwCheckBullet(text: 'WireGuard encryption'),
          const SwCheckBullet(text: 'No third-party trackers'),
          const SwCheckBullet(text: 'Native Linux client'),
          const Spacer(),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Application shell
/// ---------------------------------------------------------------------------

const _destinations = <SwDestination>[
  SwDestination(label: 'Home', icon: SwIconKind.home),
  SwDestination(label: 'Account', icon: SwIconKind.account),
  SwDestination(label: 'Diagnostics', icon: SwIconKind.pulse),
];

class _MainShell extends ConsumerStatefulWidget {
  const _MainShell();

  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell> {
  int _index = 0;

  void _select(int next) => setState(() => _index = next);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < SwLayout.compactMax;
    final connected = ref.watch(vpnStateProvider).status == VpnStatus.connected;

    // The old UI watched this from the landing tab, so /auth/me was fetched
    // immediately after login and refetched by the invalidate() calls in
    // _submit and _signOut. Watching it here keeps that timing unchanged even
    // though the details are only rendered on the Account screen.
    ref.watch(currentUserProvider);

    final content = switch (_index) {
      0 => const _HomeScreen(),
      1 => _AccountScreen(onOpenDiagnostics: () => _select(2)),
      _ => const _DiagnosticsScreen(),
    };

    final main = Column(
      children: [
        _TopBar(compact: compact),
        Expanded(child: content),
      ],
    );

    if (compact) {
      return Scaffold(
        body: SafeArea(bottom: false, child: main),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: [
            for (final destination in _destinations)
              NavigationDestination(
                icon: SwIcon(kind: destination.icon),
                selectedIcon: SwIcon(
                  kind: destination.icon,
                  color: SwColors.primaryStrong,
                ),
                label: destination.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          SwNavRail(
            destinations: _destinations,
            index: _index,
            onSelected: _select,
            connected: connected,
          ),
          Expanded(child: SafeArea(left: false, child: main)),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);

    return Container(
      height: SwLayout.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: SwSpacing.md),
      decoration: const BoxDecoration(
        color: SwColors.surface,
        border: Border(bottom: BorderSide(color: SwColors.border)),
      ),
      child: Row(
        children: [
          if (compact) ...[
            const SwLogo(size: 26),
            const SizedBox(width: 10),
          ],
          // Flexible so a very narrow window ellipsises instead of overflowing.
          const Flexible(
            child: Text(
              'SecureWave',
              overflow: TextOverflow.ellipsis,
              style: SwType.wordmark,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => unawaited(_openExternalLink(
              context,
              ref,
              AppConstants.supportUrlFallback,
            )),
            child: const Text('Help'),
          ),
          const SizedBox(width: 8),
          if (config.useMockApi) const SwStatusPill(text: 'Demo mode'),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Home — the connect surface
/// ---------------------------------------------------------------------------

class _HomeScreen extends ConsumerStatefulWidget {
  const _HomeScreen();

  @override
  ConsumerState<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<_HomeScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncTicker(ref.read(vpnStateProvider));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Drives the live session duration. Only runs while a tunnel is up and a
  /// start time actually exists, so an idle or boot-restored session costs
  /// nothing.
  void _syncTicker(VpnState vpn) {
    final wantTicker =
        vpn.status == VpnStatus.connected && vpn.lastTunnelStartAt != null;
    if (wantTicker && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!wantTicker && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vpn = ref.watch(vpnStateProvider);
    final plan = ref.watch(userPlanProvider);
    final servers = ref.watch(serversProvider);
    final config = ref.watch(appConfigProvider);
    final service = ref.watch(vpnServiceProvider);

    final serverList = servers.maybeWhen(
      data: (value) => value,
      orElse: () => const <ServerRegion>[],
    );

    final connected = vpn.status == VpnStatus.connected;
    final busy = vpn.isBusy ||
        vpn.status == VpnStatus.connecting ||
        vpn.status == VpnStatus.disconnecting;

    // Start/stop the ticker from a listener rather than from build(), so
    // building the widget stays free of side effects.
    ref.listen<VpnState>(vpnStateProvider, (_, next) => _syncTicker(next));

    final protocolAvailable = _protocolIsAvailable(
      service: service,
      servers: serverList,
      selectedServerId: vpn.selectedServerId,
      protocol: vpn.protocol,
    );

    final serverLabel = _serverLabel(vpn.selectedServerId, serverList);
    final dataUsed = plan.maybeWhen(
      data: (value) => '${value.usedGb.toStringAsFixed(1)} GB',
      orElse: () => '—',
    );

    final stats = connected
        ? <SwStat>[
            SwStat(label: 'Server', value: serverLabel),
            SwStat(label: 'Duration', value: _sessionDuration(vpn)),
            SwStat(label: 'Data used', value: dataUsed),
            SwStat(
              label: 'Health',
              value: _healthLabel(vpn.stabilityScore),
              highlight: true,
            ),
          ]
        : <SwStat>[
            SwStat(label: 'Server', value: serverLabel),
            SwStat(label: 'Protocol', value: vpnProtocolLabel(vpn.protocol)),
            SwStat(label: 'Data used', value: dataUsed),
            SwStat(label: 'Status', value: _idleLabel(vpn)),
          ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: SwSpacing.md,
            vertical: SwSpacing.md,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - SwSpacing.xl)
                  .clamp(0, double.infinity),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: SwLayout.contentMaxWidth),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SwStatusPill(
                      text: connected
                          ? 'Encrypted · WireGuard'
                          : _idlePillText(vpn, serverLabel),
                      success: connected,
                    ),
                    const SizedBox(height: 22),
                    SwConnectButton(
                      connected: connected,
                      busy: busy,
                      label: _connectLabel(vpn),
                      onPressed: busy || (!connected && !protocolAvailable)
                          ? null
                          : () {
                              final notifier =
                                  ref.read(vpnStateProvider.notifier);
                              connected
                                  ? unawaited(notifier.disconnect())
                                  : unawaited(notifier.connect());
                            },
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SwStatusDot(active: connected),
                        const SizedBox(width: 8),
                        Text(
                          _statusHeadline(vpn),
                          style: SwType.body.copyWith(
                            fontWeight: FontWeight.w700,
                            color: connected
                                ? SwColors.primaryStrong
                                : SwColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _statusHelper(vpn),
                      textAlign: TextAlign.center,
                      style: SwType.body,
                    ),
                    const SizedBox(height: 22),
                    SwInfoCard(stats: stats),
                    ..._catalogNotices(servers),
                    if (!connected && !protocolAvailable) ...[
                      const SizedBox(height: SwSpacing.sm),
                      SwNotice(
                        title: 'Connection unavailable',
                        message: _protocolUnavailableReason(
                          service: service,
                          servers: serverList,
                          selectedServerId: vpn.selectedServerId,
                          protocol: vpn.protocol,
                        ),
                        tone: SwNoticeTone.warning,
                      ),
                    ],
                    if (vpn.errorMessage != null) ...[
                      const SizedBox(height: SwSpacing.sm),
                      SwNotice(
                        title: 'Last attempt failed',
                        message: vpn.errorMessage,
                        tone: SwNoticeTone.error,
                      ),
                    ],
                    if (config.useMockApi) ...[
                      const SizedBox(height: SwSpacing.sm),
                      const SwNotice(
                        title: 'Demo mode',
                        message:
                            'Do not treat a demo connection as a real tunnel.',
                        tone: SwNoticeTone.warning,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _catalogNotices(AsyncValue<List<ServerRegion>> servers) {
    return servers.when(
      loading: () => const <Widget>[],
      error: (error, _) => <Widget>[
        const SizedBox(height: SwSpacing.sm),
        SwNotice(
          title: 'Regions unavailable',
          message: ApiError.messageFrom(
            error,
            fallback: 'The server list could not be loaded.',
          ),
          tone: SwNoticeTone.warning,
        ),
      ],
      data: (items) => items.isEmpty
          ? const <Widget>[
              SizedBox(height: SwSpacing.sm),
              SwNotice(
                title: 'No regions available',
                message:
                    'Auto-select will stay active until the catalog returns.',
                tone: SwNoticeTone.warning,
              ),
            ]
          : const <Widget>[],
    );
  }
}

/// ---------------------------------------------------------------------------
/// Account / settings
/// ---------------------------------------------------------------------------

class _AccountScreen extends ConsumerWidget {
  const _AccountScreen({required this.onOpenDiagnostics});

  final VoidCallback onOpenDiagnostics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final plan = ref.watch(userPlanProvider);
    final config = ref.watch(appConfigProvider);
    final device = ref.watch(deviceInfoProvider);
    final vpn = ref.watch(vpnStateProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SwSpacing.md,
        SwSpacing.lg,
        SwSpacing.md,
        SwSpacing.xl,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: SwLayout.contentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwPanel(
                  padding: const EdgeInsets.all(24),
                  child: user.when(
                    data: (value) => _AccountHeader(account: value),
                    loading: () => const _LoadingLine('Loading account'),
                    error: (_, __) => const SwNotice(
                      title: 'Account unavailable',
                      message: 'Account details could not be loaded.',
                      tone: SwNoticeTone.warning,
                    ),
                  ),
                ),
                const SizedBox(height: SwSpacing.md),
                const SwSectionLabel('Usage'),
                plan.when(
                  data: (value) => SwRowPanel(rows: _usageRows(value)),
                  loading: () => const SwPanel(
                    padding: EdgeInsets.all(24),
                    child: _LoadingLine('Loading usage'),
                  ),
                  error: (_, __) => const SwNotice(
                    title: 'Usage unavailable',
                    message: 'Usage could not be loaded.',
                    tone: SwNoticeTone.warning,
                  ),
                ),
                const SizedBox(height: SwSpacing.md),
                const SwSectionLabel('Runtime'),
                SwRowPanel(
                  rows: [
                    SwRow(
                      label: 'Protocol',
                      value: vpnProtocolLabel(vpn.protocol),
                    ),
                    SwRow(label: 'Device', value: device),
                    SwRow(label: 'API', value: config.apiBaseUrl),
                    SwRow(
                      label: 'Demo mode',
                      value: config.useMockApi ? 'On' : 'Off',
                    ),
                  ],
                ),
                const SizedBox(height: SwSpacing.md),
                const SwSectionLabel('Support'),
                SwRowPanel(
                  rows: [
                    SwRow(
                      label: 'Diagnostics',
                      onTap: onOpenDiagnostics,
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: SwColors.textSecondary,
                      ),
                    ),
                    SwRow(
                      label: 'Help & support',
                      onTap: () => unawaited(_openExternalLink(
                        context,
                        ref,
                        AppConstants.supportUrlFallback,
                      )),
                      trailing: const Icon(
                        Icons.open_in_new_rounded,
                        size: 18,
                        color: SwColors.textSecondary,
                      ),
                    ),
                    SwRow(
                      label: 'Account portal',
                      onTap: () => unawaited(
                        _openExternalLink(context, ref, config.portalUrl),
                      ),
                      trailing: const Icon(
                        Icons.open_in_new_rounded,
                        size: 18,
                        color: SwColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: SwSpacing.lg),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: () => _signOut(ref),
                    child: const Text('Log out'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _usageRows(UserPlan plan) {
    final percent = plan.usagePercent.isFinite
        ? plan.usagePercent.clamp(0.0, 1.0).toDouble()
        : 0.0;
    final percentText =
        plan.isUnlimited ? 'Unlimited' : '${(percent * 100).round()}%';
    final cap = plan.isUnlimited || plan.dataCapGb <= 0
        ? 'Unlimited'
        : '${plan.dataCapGb.toStringAsFixed(0)} GB';

    return [
      SwRow(label: 'Plan', value: plan.name),
      SwRow(label: 'Used', value: '${plan.usedGb.toStringAsFixed(1)} GB'),
      SwRow(label: 'Cap', value: cap),
      SwRow(label: 'Usage', value: percentText),
    ];
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.account});

  final UserAccount account;

  @override
  Widget build(BuildContext context) {
    final email = account.email.isEmpty ? 'Signed in' : account.email;
    final initial = email.isEmpty ? '?' : email.substring(0, 1).toUpperCase();

    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: SwColors.primarySoft,
          ),
          child: Text(
            initial,
            style: SwType.title.copyWith(color: SwColors.primaryStrong),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SwType.body.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: SwColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const SwStatusPill(text: 'Beta'),
                  const SizedBox(width: 8),
                  Text(
                    account.isActive ? 'Active' : 'Inactive',
                    style: SwType.footnote,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// Diagnostics
/// ---------------------------------------------------------------------------

class _DiagnosticsScreen extends ConsumerWidget {
  const _DiagnosticsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnStateProvider);
    final service = ref.watch(vpnServiceProvider);
    final servers = ref.watch(serversProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SwSpacing.md,
        SwSpacing.lg,
        SwSpacing.md,
        SwSpacing.xl,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: SwLayout.contentMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Diagnostics', style: SwType.title),
                const SizedBox(height: 6),
                const Text(
                  'Runtime facts for support. No credentials are shown.',
                  style: SwType.body,
                ),
                const SizedBox(height: SwSpacing.md),
                SwRowPanel(
                  rows: [
                    SwRow(label: 'VPN state', value: _statusHeadline(vpn)),
                    SwRow(
                      label: 'Native bridge',
                      value: service.isNativeAvailable
                          ? 'Available'
                          : 'Unavailable',
                    ),
                    SwRow(
                      label: 'Protocol',
                      value: vpnProtocolLabel(vpn.protocol),
                    ),
                    SwRow(
                      label: 'Desired state',
                      value: vpn.desiredOn ? 'On' : 'Off',
                    ),
                    SwRow(
                      label: 'Profile fetch',
                      value: vpn.lastProfileFetchOk == null
                          ? 'Not run'
                          : vpn.lastProfileFetchOk!
                              ? 'Last fetch passed'
                              : 'Last fetch failed',
                    ),
                    SwRow(
                      label: 'Tunnel start',
                      value: vpn.lastTunnelStartOk == null
                          ? 'Not run'
                          : vpn.lastTunnelStartOk!
                              ? 'Last start passed'
                              : 'Last start failed',
                    ),
                    SwRow(
                      label: 'Regions',
                      value: servers.when(
                        data: (items) => '${items.length} loaded',
                        loading: () => 'Loading',
                        error: (_, __) => 'Load failed',
                      ),
                    ),
                  ],
                ),
                if (vpn.errorMessage != null) ...[
                  const SizedBox(height: SwSpacing.md),
                  SwNotice(
                    title: 'Last error',
                    message: vpn.errorMessage,
                    tone: SwNoticeTone.error,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// Boot + shared bits
/// ---------------------------------------------------------------------------

class _BootView extends StatelessWidget {
  const _BootView({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SwColors.surface,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SwLogo(size: 46),
              const SizedBox(height: SwSpacing.md),
              const Text('Starting SecureWave', style: SwType.title),
              const SizedBox(height: SwSpacing.sm),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              if (message != null) ...[
                const SizedBox(height: SwSpacing.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: SwType.footnote,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingLine extends StatelessWidget {
  const _LoadingLine(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text(label, style: SwType.body),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// Presentation helpers
/// ---------------------------------------------------------------------------

bool _protocolIsAvailable({
  required VpnService service,
  required List<ServerRegion> servers,
  required String? selectedServerId,
  required VpnProtocol protocol,
}) {
  if (!service.canConnectProtocol(protocol)) return false;
  final selected = selectedServerId == null
      ? const <ServerRegion>[]
      : servers.where((server) => server.id == selectedServerId).toList();
  // Treat an ID that no longer exists in the catalog as auto-select. The
  // state layer will clear it if the backend also rejects the reference.
  final candidates = selected.isEmpty ? servers : selected;
  return candidates.any(
    (server) => server.supportsProtocol(vpnProtocolStorageValue(protocol)),
  );
}

String _protocolUnavailableReason({
  required VpnService service,
  required List<ServerRegion> servers,
  required String? selectedServerId,
  required VpnProtocol protocol,
}) {
  final nativeReason = service.protocolUnavailableReason(protocol);
  if (nativeReason != null) return nativeReason;
  final selectedExists = selectedServerId != null &&
      servers.any((server) => server.id == selectedServerId);
  final scope = selectedExists ? 'selected server' : 'server catalog';
  return 'No verified ${vpnProtocolLabel(protocol)} evidence exists for the $scope.';
}

String _serverLabel(String? selectedServerId, List<ServerRegion> servers) {
  if (selectedServerId == null) {
    if (servers.length == 1) return servers.first.name;
    return 'Auto-select';
  }
  for (final server in servers) {
    if (server.id == selectedServerId) return server.name;
  }
  return 'Auto-select';
}

String _statusHeadline(VpnState vpn) {
  final backendUnreachable = vpn.status == VpnStatus.error &&
      vpn.errorKind == VpnErrorKind.backendUnreachable;
  return switch (vpn.status) {
    VpnStatus.connected => 'Connected',
    VpnStatus.connecting => 'Connecting',
    VpnStatus.disconnecting => 'Disconnecting',
    VpnStatus.error =>
      backendUnreachable ? 'Backend unreachable' : 'Needs attention',
    VpnStatus.disconnected => 'Not connected',
  };
}

String _statusHelper(VpnState vpn) {
  return switch (vpn.status) {
    // A session restored at boot reports connected without a recorded start
    // time, so only claim a duration when one actually exists.
    VpnStatus.connected => vpn.lastTunnelStartAt == null
        ? 'Your traffic is routed through WireGuard'
        : 'Session started ${_sessionDuration(vpn)} ago',
    VpnStatus.connecting => 'Bringing up the WireGuard tunnel',
    VpnStatus.disconnecting => 'Closing the tunnel',
    VpnStatus.error => 'Review the details below and try again',
    VpnStatus.disconnected => 'Tap connect to start a secure session',
  };
}

String _connectLabel(VpnState vpn) {
  return switch (vpn.status) {
    VpnStatus.connected => 'DISCONNECT',
    VpnStatus.connecting => 'CONNECTING',
    VpnStatus.disconnecting => 'STOPPING',
    _ => 'CONNECT',
  };
}

String _idleLabel(VpnState vpn) {
  return switch (vpn.status) {
    VpnStatus.error => 'Error',
    VpnStatus.connecting => 'Starting',
    VpnStatus.disconnecting => 'Stopping',
    _ => 'Idle',
  };
}

String _idlePillText(VpnState vpn, String serverLabel) {
  return '${vpnProtocolLabel(vpn.protocol)} · $serverLabel';
}

String _sessionDuration(VpnState vpn) {
  final started = vpn.lastTunnelStartAt;
  if (started == null) return '—';
  final elapsed = DateTime.now().difference(started);
  if (elapsed.isNegative) return '—';
  final hours = elapsed.inHours;
  final minutes = elapsed.inMinutes.remainder(60);
  final seconds = elapsed.inSeconds.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}

String _healthLabel(double stabilityScore) {
  if (stabilityScore >= 0.9) return 'Excellent';
  if (stabilityScore >= 0.7) return 'Good';
  if (stabilityScore >= 0.4) return 'Fair';
  return 'Degraded';
}

Future<void> _signOut(WidgetRef ref) async {
  final vpn = ref.read(vpnStateProvider);
  if (!vpn.isBusy && vpn.status != VpnStatus.disconnected) {
    await ref.read(vpnStateProvider.notifier).disconnect();
  }
  await SecureStorage().clearVpnRuntimeState();
  await ref.read(authSessionProvider).clearSession();
  await ref.read(vpnStateProvider.notifier).resetConnectionSelection();
  ref.invalidate(currentUserProvider);
  ref.invalidate(userPlanProvider);
  ref.invalidate(serversProvider);
}

Future<void> _openExternalLink(
  BuildContext context,
  WidgetRef ref,
  String url,
) async {
  final opened = await ref.read(externalLinksProvider).openUrl(url);
  if (opened || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Could not open that link. Please try again.'),
    ),
  );
}

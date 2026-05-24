import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/bootstrap/boot_controller.dart';
import 'core/config/app_config.dart';
import 'core/logging/app_logger.dart';
import 'core/models/server_region.dart';
import 'core/models/user_account.dart';
import 'core/models/user_plan.dart';
import 'core/models/vpn_protocol.dart';
import 'core/models/vpn_status.dart';
import 'core/services/auth_session.dart';
import 'core/state/app_state.dart';
import 'core/state/vpn_state.dart';
import 'core/utils/api_error.dart';
import 'services/auth_service.dart';
import 'services/external_links.dart';

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
      theme: FreshTheme.theme,
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

class FreshTheme {
  static const background = Color(0xFF050914);
  static const surface = Color(0xFF0C1424);
  static const surfaceMuted = Color(0xFF121D31);
  static const graphite = Color(0xFFF7FAFF);
  static const graphiteMuted = Color(0xFFB7C4D8);
  static const line = Color(0xFF23314B);
  static const lineStrong = Color(0xFF34466A);
  static const primary = Color(0xFF3B82F6);
  static const primarySoft = Color(0xFF102A4D);
  static const amber = Color(0xFFF4B04B);
  static const amberSoft = Color(0xFF34270E);
  static const red = Color(0xFFFF6B6B);
  static const redSoft = Color(0xFF351417);
  static const secondary = Color(0xFFFFFFFF);
  static const secondarySoft = Color(0xFF1C2A3E);

  static const radius = 10.0;
  static const radiusSmall = 8.0;
  static const maxWidth = 1160.0;
  static const mobileMax = 760.0;

  static ThemeData get theme {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: primary,
      onPrimary: Colors.white,
      secondary: secondary,
      surface: surface,
      onSurface: graphite,
      error: red,
      outline: line,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: null,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 25,
          height: 1.16,
          fontWeight: FontWeight.w700,
          color: graphite,
        ),
        titleLarge: TextStyle(
          fontSize: 19,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: graphite,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: graphite,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.42,
          color: graphite,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.38,
          color: graphiteMuted,
        ),
        bodySmall: TextStyle(
          fontSize: 12.5,
          height: 1.32,
          color: graphiteMuted,
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: surface,
        foregroundColor: graphite,
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: graphite,
          minimumSize: const Size(0, 44),
          side: const BorderSide(color: lineStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: primary, width: 1.4),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: surface,
        indicatorColor: primarySoft,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight:
                states.contains(WidgetState.selected) ? FontWeight.w700 : null,
            color: graphite,
          ),
        ),
      ),
    );
  }
}

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

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = _register
        ? 'Create an account to start using SecureWave.'
        : 'Sign in to manage your VPN session.';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _PlainPanel(
                padding: const EdgeInsets.all(22),
                child: Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'SecureWave',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(copy,
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 22),
                        TextFormField(
                          controller: _email,
                          autofillHints: const [
                            AutofillHints.username,
                            AutofillHints.email,
                          ],
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration:
                              const InputDecoration(labelText: 'Email address'),
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
                        const SizedBox(height: 12),
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
                              icon: Icon(_hidePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
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
                            return null;
                          },
                        ),
                        if (_register) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _confirm,
                            obscureText: true,
                            autofillHints: const [AutofillHints.newPassword],
                            textInputAction: TextInputAction.done,
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
                          const SizedBox(height: 14),
                          _InlineMessage(
                            icon: Icons.warning_amber_rounded,
                            message: _error!,
                            tone: _Tone.error,
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(_register ? 'Create account' : 'Sign in'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  setState(() {
                                    _register = !_register;
                                    _error = null;
                                  });
                                },
                          child: Text(
                            _register
                                ? 'Use an existing account'
                                : 'Create a new account',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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

class _MainShell extends ConsumerStatefulWidget {
  const _MainShell();

  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell> {
  int _index = 0;

  static const _tabs = [
    _ShellTab('Connect', Icons.power_settings_new_rounded),
    _ShellTab('Servers', Icons.public_rounded),
    _ShellTab('Account', Icons.person_rounded),
    _ShellTab('Settings', Icons.tune_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= FreshTheme.mobileMax;
    final title = _tabs[_index].label;
    final child = switch (_index) {
      0 => const _ConnectScreen(),
      1 => const _ServersScreen(),
      2 => const _AccountScreen(),
      _ => const _SettingsScreen(),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: wide
            ? PreferredSize(
                preferredSize: const Size.fromHeight(50),
                child: _TopTabs(
                  tabs: _tabs,
                  index: _index,
                  onChanged: (next) => setState(() => _index = next),
                ),
              )
            : null,
      ),
      body: _PageFrame(child: child),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (next) => setState(() => _index = next),
              destinations: [
                for (final tab in _tabs)
                  NavigationDestination(
                    icon: Icon(tab.icon),
                    label: tab.label,
                  ),
              ],
            ),
    );
  }
}

class _TopTabs extends StatelessWidget {
  const _TopTabs({
    required this.tabs,
    required this.index,
    required this.onChanged,
  });

  final List<_ShellTab> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: FreshTheme.line)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                _TopTabButton(
                  tab: tabs[i],
                  selected: index == i,
                  onTap: () => onChanged(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopTabButton extends StatelessWidget {
  const _TopTabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _ShellTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 49,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? FreshTheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              tab.icon,
              size: 18,
              color: selected ? FreshTheme.primary : FreshTheme.graphiteMuted,
            ),
            const SizedBox(width: 8),
            Text(
              tab.label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color:
                    selected ? FreshTheme.graphite : FreshTheme.graphiteMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectScreen extends ConsumerWidget {
  const _ConnectScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnStateProvider);
    final user = ref.watch(currentUserProvider);
    final plan = ref.watch(userPlanProvider);
    final servers = ref.watch(serversProvider);
    final config = ref.watch(appConfigProvider);

    final serverList = servers.maybeWhen(
      data: (value) => value,
      orElse: () => const <ServerRegion>[],
    );
    final selectedServer = _serverLabel(vpn.selectedServerId, serverList);
    final status = _statusDescriptor(vpn);
    final connected = vpn.status == VpnStatus.connected;
    final busy = vpn.isBusy ||
        vpn.status == VpnStatus.connecting ||
        vpn.status == VpnStatus.disconnecting;

    return ListView(
      children: [
        _PlainPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AccountLine(user: user),
              const SizedBox(height: 18),
              _ConnectionStrip(status: status, protocol: vpn.protocol),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () {
                              final notifier =
                                  ref.read(vpnStateProvider.notifier);
                              connected
                                  ? unawaited(notifier.disconnect())
                                  : unawaited(notifier.connect());
                            },
                      icon: Icon(connected
                          ? Icons.stop_rounded
                          : Icons.power_settings_new_rounded),
                      label: Text(connected ? 'Disconnect' : 'Connect'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () => _showDiagnostics(context),
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: const Text('Diagnostics'),
                  ),
                ],
              ),
              if (vpn.errorMessage != null) ...[
                const SizedBox(height: 12),
                _InlineMessage(
                  icon: Icons.error_outline_rounded,
                  message: vpn.errorMessage!,
                  tone: _Tone.error,
                ),
              ],
              if (config.useMockApi) ...[
                const SizedBox(height: 12),
                const _InlineMessage(
                  icon: Icons.info_outline_rounded,
                  message:
                      'Demo API mode is enabled. Do not treat a demo connection as a real tunnel.',
                  tone: _Tone.warning,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _ResponsivePair(
          left: _PlainPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Session'),
                const SizedBox(height: 12),
                _InfoRow('Server', selectedServer),
                _InfoRow('Protocol', vpnProtocolLabel(vpn.protocol)),
                _InfoRow(
                    'Download', '${vpn.dataRateDown.toStringAsFixed(1)} Mbps'),
                _InfoRow('Upload', '${vpn.dataRateUp.toStringAsFixed(1)} Mbps'),
              ],
            ),
          ),
          right: _PlainPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Data'),
                const SizedBox(height: 12),
                plan.when(
                  data: (value) => _UsageSummary(plan: value),
                  loading: () => const _LoadingLine('Loading usage'),
                  error: (_, __) => const _InlineMessage(
                    icon: Icons.warning_amber_rounded,
                    message: 'Usage could not be loaded.',
                    tone: _Tone.warning,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _PlainPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Protocol'),
              const SizedBox(height: 12),
              _ProtocolPicker(selected: vpn.protocol),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServersScreen extends ConsumerWidget {
  const _ServersScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final vpn = ref.watch(vpnStateProvider);

    return servers.when(
      loading: () => const _CenteredState(
        icon: Icons.public_rounded,
        title: 'Loading regions',
        body: 'SecureWave is requesting the server catalog.',
      ),
      error: (error, _) => _CenteredState(
        icon: Icons.cloud_off_rounded,
        title: 'Regions unavailable',
        body: ApiError.messageFrom(
          error,
          fallback: 'The server list could not be loaded.',
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const _CenteredState(
            icon: Icons.public_off_rounded,
            title: 'No regions available',
            body: 'Auto-select will stay active until the catalog returns.',
          );
        }

        return ListView(
          children: [
            _PlainPanel(
              child: _ServerTile(
                title: 'Auto-select',
                subtitle: 'Choose the best region at connect time.',
                selected: vpn.selectedServerId == null,
                icon: Icons.auto_awesome_rounded,
                onTap: () =>
                    ref.read(vpnStateProvider.notifier).selectServer(null),
              ),
            ),
            const SizedBox(height: 10),
            for (final server in items) ...[
              _PlainPanel(
                child: _ServerTile(
                  title: server.name,
                  subtitle: _serverSubtitle(server),
                  selected: vpn.selectedServerId == server.id,
                  icon: Icons.public_rounded,
                  onTap: () => ref
                      .read(vpnStateProvider.notifier)
                      .selectServer(server.id),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _AccountScreen extends ConsumerWidget {
  const _AccountScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final plan = ref.watch(userPlanProvider);

    return ListView(
      children: [
        _PlainPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Account'),
              const SizedBox(height: 12),
              user.when(
                data: (value) => Column(
                  children: [
                    _InfoRow('Email',
                        value.email.isEmpty ? 'Signed in' : value.email),
                    _InfoRow('Status', value.isActive ? 'Active' : 'Inactive'),
                    _InfoRow(
                      'Verification',
                      value.emailVerified
                          ? 'Email verified'
                          : 'Email unverified',
                    ),
                    _InfoRow('Plan', value.subscriptionStatus),
                  ],
                ),
                loading: () => const _LoadingLine('Loading account'),
                error: (_, __) => const _InlineMessage(
                  icon: Icons.warning_amber_rounded,
                  message: 'Account details could not be loaded.',
                  tone: _Tone.warning,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PlainPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Usage'),
              const SizedBox(height: 12),
              plan.when(
                data: (value) => _UsageSummary(plan: value),
                loading: () => const _LoadingLine('Loading usage'),
                error: (_, __) => const _InlineMessage(
                  icon: Icons.warning_amber_rounded,
                  message: 'Usage could not be loaded.',
                  tone: _Tone.warning,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsScreen extends ConsumerWidget {
  const _SettingsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final device = ref.watch(deviceInfoProvider);
    final vpn = ref.watch(vpnStateProvider);

    return ListView(
      children: [
        _PlainPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Runtime'),
              const SizedBox(height: 12),
              _InfoRow('Device', device),
              _InfoRow('API', config.apiBaseUrl),
              _InfoRow('Mock API', config.useMockApi ? 'On' : 'Off'),
              _InfoRow('Protocol', vpnProtocolLabel(vpn.protocol)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _PlainPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showDiagnostics(context),
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('Open diagnostics'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(externalLinksProvider).openUrl(config.portalUrl),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open account portal'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => _signOut(context, ref),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DiagnosticsView extends ConsumerWidget {
  const _DiagnosticsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnStateProvider);
    final service = ref.watch(vpnServiceProvider);
    final serverList = ref.watch(serversProvider);

    return ListView(
      shrinkWrap: true,
      children: [
        _InfoRow('VPN state', _statusDescriptor(vpn).label),
        _InfoRow('Native bridge',
            service.isNativeAvailable ? 'Available' : 'Unavailable'),
        _InfoRow('Protocol', vpnProtocolLabel(vpn.protocol)),
        _InfoRow('Desired state', vpn.desiredOn ? 'On' : 'Off'),
        _InfoRow(
          'Profile fetch',
          vpn.lastProfileFetchOk == null
              ? 'Not run'
              : vpn.lastProfileFetchOk!
                  ? 'Last fetch passed'
                  : 'Last fetch failed',
        ),
        _InfoRow(
          'Tunnel start',
          vpn.lastTunnelStartOk == null
              ? 'Not run'
              : vpn.lastTunnelStartOk!
                  ? 'Last start passed'
                  : 'Last start failed',
        ),
        serverList.when(
          data: (items) => _InfoRow('Regions', '${items.length} loaded'),
          loading: () => const _InfoRow('Regions', 'Loading'),
          error: (_, __) => const _InfoRow('Regions', 'Load failed'),
        ),
        if (vpn.errorMessage != null)
          _InlineMessage(
            icon: Icons.error_outline_rounded,
            message: vpn.errorMessage!,
            tone: _Tone.error,
          ),
      ],
    );
  }
}

class _ProtocolPicker extends ConsumerWidget {
  const _ProtocolPicker({required this.selected});

  final VpnProtocol selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _ProtocolTile(
          protocol: VpnProtocol.wireGuard,
          selected: selected == VpnProtocol.wireGuard,
          title: 'WireGuard',
          detail: 'Primary Linux runtime path.',
          enabled: true,
        ),
        const SizedBox(height: 8),
        _ProtocolTile(
          protocol: VpnProtocol.openVpn,
          selected: selected == VpnProtocol.openVpn,
          title: 'OpenVPN',
          detail: 'Requires a backend-issued OpenVPN profile.',
          enabled: true,
        ),
        const SizedBox(height: 8),
        _ProtocolTile(
          protocol: VpnProtocol.ikev2,
          selected: selected == VpnProtocol.ikev2,
          title: 'IKEv2/IPSec',
          detail: 'Not wired in the Linux runner yet.',
          enabled: false,
        ),
      ],
    );
  }
}

class _ProtocolTile extends ConsumerWidget {
  const _ProtocolTile({
    required this.protocol,
    required this.selected,
    required this.title,
    required this.detail,
    required this.enabled,
  });

  final VpnProtocol protocol;
  final bool selected;
  final String title;
  final String detail;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SelectableRow(
      selected: selected,
      enabled: enabled,
      title: title,
      subtitle: detail,
      trailing: enabled
          ? null
          : const _StatusChip(label: 'Unavailable', tone: _Tone.warning),
      onTap: enabled
          ? () => ref.read(vpnStateProvider.notifier).selectProtocol(protocol)
          : null,
    );
  }
}

class _ConnectionStrip extends StatelessWidget {
  const _ConnectionStrip({required this.status, required this.protocol});

  final _StatusDescriptor status;
  final VpnProtocol protocol;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: status.background,
        border: Border.all(color: status.border),
        borderRadius: BorderRadius.circular(FreshTheme.radius),
      ),
      child: Row(
        children: [
          Icon(status.icon, color: status.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status.label,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  vpnProtocolLabel(protocol),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          _StatusChip(label: status.shortLabel, tone: status.tone),
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
    final percent = plan.usagePercent.isFinite
        ? plan.usagePercent.clamp(0.0, 1.0).toDouble()
        : 0.0;
    final percentText =
        plan.isUnlimited ? 'Unlimited' : '${(percent * 100).round()}%';
    final cap = plan.isUnlimited || plan.dataCapGb <= 0
        ? 'Unlimited'
        : '${plan.dataCapGb.toStringAsFixed(0)} GB';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                plan.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _StatusChip(
              label: plan.isPremium ? 'Premium' : 'Free',
              tone: plan.isPremium ? _Tone.info : _Tone.neutral,
            ),
          ],
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: plan.isUnlimited ? 1 : percent,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
          color: FreshTheme.primary,
          backgroundColor: FreshTheme.surfaceMuted,
        ),
        const SizedBox(height: 12),
        _InfoRow('Used', '${plan.usedGb.toStringAsFixed(1)} GB'),
        _InfoRow('Cap', cap),
        _InfoRow('Usage', percentText),
      ],
    );
  }
}

class _PlainPanel extends StatelessWidget {
  const _PlainPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FreshTheme.surface,
        border: Border.all(color: FreshTheme.line),
        borderRadius: BorderRadius.circular(FreshTheme.radius),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: FreshTheme.maxWidth),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= FreshTheme.mobileMax;
    if (!wide) {
      return Column(
        children: [
          left,
          const SizedBox(height: 14),
          right,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 14),
        Expanded(child: right),
      ],
    );
  }
}

class _AccountLine extends StatelessWidget {
  const _AccountLine({required this.user});

  final AsyncValue<UserAccount> user;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.person_outline_rounded, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            user.maybeWhen(
              data: (value) => value.email.isEmpty ? 'Signed in' : value.email,
              loading: () => 'Loading account',
              orElse: () => 'Account unavailable',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _SelectableRow(
      selected: selected,
      enabled: true,
      title: title,
      subtitle: subtitle,
      leading: Icon(icon,
          color: selected ? FreshTheme.primary : FreshTheme.graphiteMuted),
      onTap: onTap,
    );
  }
}

class _SelectableRow extends StatelessWidget {
  const _SelectableRow({
    required this.selected,
    required this.enabled,
    required this.title,
    required this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final bool selected;
  final bool enabled;
  final String title;
  final String subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(FreshTheme.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? FreshTheme.primarySoft : Colors.transparent,
          border: Border.all(
            color: selected ? FreshTheme.primary : FreshTheme.line,
          ),
          borderRadius: BorderRadius.circular(FreshTheme.radiusSmall),
        ),
        child: Row(
          children: [
            leading ??
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color:
                      selected ? FreshTheme.primary : FreshTheme.graphiteMuted,
                ),
            const SizedBox(width: 12),
            Expanded(
              child: Opacity(
                opacity: enabled ? 1 : 0.62,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: FreshTheme.graphite,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.tone});

  final String label;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final colors = _toneColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.icon,
    required this.message,
    required this.tone,
  });

  final IconData icon;
  final String message;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final colors = _toneColors(tone);
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(FreshTheme.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.foreground),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _PlainPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: FreshTheme.graphiteMuted),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _BootView extends StatelessWidget {
  const _BootView({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: _PlainPanel(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(height: 14),
                Text(
                  'Starting SecureWave',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
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
        const SizedBox(width: 10),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleLarge);
  }
}

class _ShellTab {
  const _ShellTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _StatusDescriptor {
  const _StatusDescriptor({
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.color,
    required this.background,
    required this.border,
    required this.tone,
  });

  final String label;
  final String shortLabel;
  final IconData icon;
  final Color color;
  final Color background;
  final Color border;
  final _Tone tone;
}

enum _Tone { neutral, info, success, warning, error }

({Color background, Color border, Color foreground}) _toneColors(_Tone tone) {
  return switch (tone) {
    _Tone.success => (
        background: FreshTheme.primarySoft,
        border: const Color(0xFF2F61A6),
        foreground: FreshTheme.primary,
      ),
    _Tone.warning => (
        background: FreshTheme.amberSoft,
        border: const Color(0xFF6B4E1C),
        foreground: FreshTheme.amber,
      ),
    _Tone.error => (
        background: FreshTheme.redSoft,
        border: const Color(0xFF6A2B31),
        foreground: FreshTheme.red,
      ),
    _Tone.info => (
        background: FreshTheme.secondarySoft,
        border: const Color(0xFF52627A),
        foreground: FreshTheme.secondary,
      ),
    _Tone.neutral => (
        background: FreshTheme.surfaceMuted,
        border: FreshTheme.line,
        foreground: FreshTheme.graphiteMuted,
      ),
  };
}

_StatusDescriptor _statusDescriptor(VpnState vpn) {
  final backendUnreachable = vpn.status == VpnStatus.error &&
      vpn.errorKind == VpnErrorKind.backendUnreachable;
  return switch (vpn.status) {
    VpnStatus.connected => const _StatusDescriptor(
        label: 'VPN connected',
        shortLabel: 'On',
        icon: Icons.verified_rounded,
        color: FreshTheme.primary,
        background: FreshTheme.primarySoft,
        border: Color(0xFF2F61A6),
        tone: _Tone.success,
      ),
    VpnStatus.connecting => const _StatusDescriptor(
        label: 'Connecting',
        shortLabel: 'Wait',
        icon: Icons.sync_rounded,
        color: FreshTheme.amber,
        background: FreshTheme.amberSoft,
        border: Color(0xFF6B4E1C),
        tone: _Tone.warning,
      ),
    VpnStatus.disconnecting => const _StatusDescriptor(
        label: 'Disconnecting',
        shortLabel: 'Wait',
        icon: Icons.sync_disabled_rounded,
        color: FreshTheme.amber,
        background: FreshTheme.amberSoft,
        border: Color(0xFF6B4E1C),
        tone: _Tone.warning,
      ),
    VpnStatus.error => _StatusDescriptor(
        label:
            backendUnreachable ? 'Backend unreachable' : 'VPN needs attention',
        shortLabel: 'Error',
        icon: Icons.warning_amber_rounded,
        color: FreshTheme.red,
        background: FreshTheme.redSoft,
        border: const Color(0xFF6A2B31),
        tone: _Tone.error,
      ),
    VpnStatus.disconnected => const _StatusDescriptor(
        label: 'VPN disconnected',
        shortLabel: 'Off',
        icon: Icons.power_settings_new_rounded,
        color: FreshTheme.graphiteMuted,
        background: FreshTheme.surfaceMuted,
        border: FreshTheme.line,
        tone: _Tone.neutral,
      ),
  };
}

String _serverLabel(String? selectedServerId, List<ServerRegion> servers) {
  if (selectedServerId == null) return 'Auto-select';
  for (final server in servers) {
    if (server.id == selectedServerId) return server.name;
  }
  return selectedServerId;
}

String _serverSubtitle(ServerRegion server) {
  final parts = <String>[];
  if (server.city != null && server.city!.isNotEmpty) parts.add(server.city!);
  if (server.country != null && server.country!.isNotEmpty) {
    parts.add(server.country!);
  }
  if (server.latencyMs != null) parts.add('${server.latencyMs} ms');
  return parts.isEmpty ? 'Region endpoint' : parts.join(' · ');
}

Future<void> _signOut(BuildContext context, WidgetRef ref) async {
  final vpn = ref.read(vpnStateProvider);
  if (vpn.status == VpnStatus.connected || vpn.status == VpnStatus.connecting) {
    await ref.read(vpnStateProvider.notifier).disconnect();
  }
  await ref.read(authSessionProvider).clearSession();
  ref.invalidate(currentUserProvider);
  ref.invalidate(userPlanProvider);
  ref.invalidate(serversProvider);
}

void _showDiagnostics(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            bottom: 18 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.76,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Diagnostics',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Expanded(child: _DiagnosticsView()),
              ],
            ),
          ),
        ),
      );
    },
  );
}

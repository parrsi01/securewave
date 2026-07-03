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
import 'core/release/platform_release_truth.dart';
import 'core/services/auth_session.dart';
import 'core/services/linux_runtime_setup.dart';
import 'core/services/secure_storage.dart';
import 'core/services/vpn_service.dart';
import 'core/state/app_state.dart';
import 'core/state/vpn_state.dart';
import 'core/utils/api_error.dart';
import 'core/utils/formatters.dart';
import 'services/auth_service.dart';
import 'services/external_links.dart';
import 'ui/app_ui_v1.dart';

typedef FreshTheme = AppUIv1;

final nativeRuntimeStatusProvider = FutureProvider<VpnRuntimeStatus>((ref) {
  return ref.read(vpnServiceProvider).refreshRuntimeStatus();
});

final linuxRuntimeInstallStateProvider =
    FutureProvider<LinuxRuntimeInstallState>((ref) {
  return ref.read(linuxRuntimeSetupProvider).getInstallState();
});

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
      final loadedConfig = await AppConfig.load();
      if (!mounted) return;
      final currentConfig = ref.read(appConfigProvider);
      final config = loadedConfig.copyWith(
        simulateTunnel:
            currentConfig.simulateTunnel || loadedConfig.simulateTunnel,
      );
      ref.read(appConfigProvider.notifier).state = config;
      ref.invalidate(nativeRuntimeStatusProvider);
      ref.invalidate(linuxRuntimeInstallStateProvider);
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
      theme: AppUIv1.theme,
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

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 46});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'SecureWave logo',
      image: true,
      child: Image.asset(
        'assets/securewave_mark.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _BrandMark(size: 58),
        const SizedBox(height: 12),
        Text(
          'SecureWave',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _BrandMark(size: 28),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _PlainPanel(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                child: Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _BrandLockup(),
                        const SizedBox(height: 16),
                        Text(
                          copy,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
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
                            if (!RegExp(r'[A-Za-z]').hasMatch(value) ||
                                !RegExp(r'[0-9]').hasMatch(value) ||
                                !RegExp(r'[^A-Za-z0-9]').hasMatch(value)) {
                              return 'Use letters, numbers, and a special character.';
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
        title: _AppBarTitle(title: title),
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
          : _BottomTabs(
              tabs: _tabs,
              index: _index,
              onChanged: (next) => setState(() => _index = next),
            ),
    );
  }
}

class _BottomTabs extends StatelessWidget {
  const _BottomTabs({
    required this.tabs,
    required this.index,
    required this.onChanged,
  });

  final List<_ShellTab> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: FreshTheme.surface,
          border: Border(top: BorderSide(color: FreshTheme.line)),
        ),
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: IconButton(
                    tooltip: tabs[i].label,
                    isSelected: i == index,
                    onPressed: () => onChanged(i),
                    color: FreshTheme.graphiteMuted,
                    selectedIcon: Icon(tabs[i].icon, color: FreshTheme.primary),
                    icon: Icon(tabs[i].icon),
                  ),
                ),
            ],
          ),
        ),
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
    final nativeRuntime = ref.watch(nativeRuntimeStatusProvider);
    final releaseTruth = SecureWaveReleaseTruth.currentPlatform();

    final serverList = servers.maybeWhen(
      data: (value) => value,
      orElse: () => const <ServerRegion>[],
    );
    final selectedServer = _serverLabel(vpn.selectedServerId, serverList);
    final status =
        _statusDescriptor(vpn, simulateTunnel: config.simulateTunnel);
    final connected = vpn.status == VpnStatus.connected;
    final busy = vpn.isBusy ||
        vpn.status == VpnStatus.connecting ||
        vpn.status == VpnStatus.disconnecting;

    return ListView(
      children: [
        _GroupedSection(
          title: 'Connection',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AccountLine(user: user),
              const SizedBox(height: 14),
              _ConnectionStrip(
                status: status,
                protocol: vpn.protocol,
                server: selectedServer,
                desiredOn: vpn.desiredOn,
              ),
              const SizedBox(height: 10),
              _PlatformTruthNotice(truth: releaseTruth),
              const _RuntimeSetupPanel(
                hideWhenInstalled: true,
                showLoading: false,
                topSpacing: 10,
              ),
              nativeRuntime.maybeWhen(
                data: (runtime) {
                  if (runtime.status != VpnStatus.connected) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _InlineMessage(
                      icon: Icons.verified_rounded,
                      message:
                          'Runtime verified: ${vpnProtocolLabel(runtime.protocol ?? vpn.protocol)} tunnel is active.',
                      tone: _Tone.success,
                    ),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),
              _ConnectionActions(
                connected: connected,
                busy: busy,
                onConnectToggle: () {
                  final notifier = ref.read(vpnStateProvider.notifier);
                  unawaited(() async {
                    connected
                        ? await notifier.disconnect()
                        : await notifier.connect();
                    ref.invalidate(nativeRuntimeStatusProvider);
                  }());
                },
                onDiagnostics: () => _showDiagnostics(context),
              ),
              if (vpn.errorMessage != null) ...[
                const SizedBox(height: 10),
                _InlineMessage(
                  icon: Icons.error_outline_rounded,
                  message: vpn.errorMessage!,
                  tone: _Tone.error,
                ),
              ],
              if (config.useMockApi) ...[
                const SizedBox(height: 10),
                const _InlineMessage(
                  icon: Icons.info_outline_rounded,
                  message:
                      'Demo API mode is enabled. Do not treat a demo connection as a real tunnel.',
                  tone: _Tone.warning,
                ),
              ],
              if (config.simulateTunnel) ...[
                const SizedBox(height: 10),
                const _InlineMessage(
                  icon: Icons.info_outline_rounded,
                  message:
                      'Simulated tunnel — presentation mode. Not a real VPN.',
                  tone: _Tone.warning,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ResponsivePair(
          left: _GroupedSection(
            title: 'Session',
            child: Column(
              children: [
                _ValueRow('Current session', _sessionUsageText(vpn)),
                _ValueRow('Down rate',
                    formatMbpsFromBytesPerSecond(vpn.dataRateDown)),
                _ValueRow(
                    'Up rate', formatMbpsFromBytesPerSecond(vpn.dataRateUp)),
                _ValueRow('Counter source', _counterSourceText(vpn)),
              ],
            ),
          ),
          right: _GroupedSection(
            title: 'Data',
            child: plan.when(
              data: (value) => _UsageSummary(
                plan: value,
                vpn: vpn,
                showMonthlyUsage: !config.useMockApi,
              ),
              loading: () => const _LoadingLine('Loading usage'),
              error: (_, __) => const _InlineMessage(
                icon: Icons.warning_amber_rounded,
                message: 'Usage could not be loaded.',
                tone: _Tone.warning,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _GroupedSection(
          title: 'Protocol',
          child: _ProtocolPicker(
            selected: vpn.protocol,
            selectedServerId: vpn.selectedServerId,
            servers: serverList,
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
            _GroupedSection(
              title: 'Servers',
              child: Column(
                children: [
                  _ServerTile(
                    title: 'Auto-select',
                    subtitle: 'Choose the best region at connect time.',
                    selected: vpn.selectedServerId == null,
                    icon: Icons.auto_awesome_rounded,
                    onTap: () =>
                        ref.read(vpnStateProvider.notifier).selectServer(null),
                  ),
                  for (final server in items) ...[
                    const SizedBox(height: 8),
                    _ServerTile(
                      title: server.name,
                      subtitle: _serverSubtitle(server),
                      selected: vpn.selectedServerId == server.id,
                      icon: Icons.public_rounded,
                      onTap: () => ref
                          .read(vpnStateProvider.notifier)
                          .selectServer(server.id),
                    ),
                  ],
                ],
              ),
            ),
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
    final config = ref.watch(appConfigProvider);
    final vpn = ref.watch(vpnStateProvider);

    return ListView(
      children: [
        _GroupedSection(
          title: 'Account',
          child: user.when(
            data: (value) => Column(
              children: [
                _AccountSummary(account: value),
                const SizedBox(height: 12),
                _ValueRow(
                    'Email', value.email.isEmpty ? 'Signed in' : value.email),
                _ValueRow('Status', value.isActive ? 'Active' : 'Inactive'),
                _ValueRow(
                  'Verification',
                  value.emailVerified ? 'Email verified' : 'Email unverified',
                ),
                _ValueRow('Plan', value.subscriptionStatus),
              ],
            ),
            loading: () => const _LoadingLine('Loading account'),
            error: (_, __) => const _InlineMessage(
              icon: Icons.warning_amber_rounded,
              message: 'Account details could not be loaded.',
              tone: _Tone.warning,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _GroupedSection(
          title: 'Usage',
          child: plan.when(
            data: (value) => _UsageSummary(
              plan: value,
              vpn: vpn,
              showMonthlyUsage: !config.useMockApi,
            ),
            loading: () => const _LoadingLine('Loading usage'),
            error: (_, __) => const _InlineMessage(
              icon: Icons.warning_amber_rounded,
              message: 'Usage could not be loaded.',
              tone: _Tone.warning,
            ),
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
    final plan = ref.watch(userPlanProvider);
    final releaseTruth = SecureWaveReleaseTruth.currentPlatform();

    return ListView(
      children: [
        _GroupedSection(
          title: 'Runtime',
          child: Column(
            children: [
              _ValueRow('Device', device),
              _ValueRow('API', config.apiBaseUrl),
              _ValueRow('Mock API', config.useMockApi ? 'On' : 'Off'),
              _ValueRow(
                'Presentation mode',
                config.simulateTunnel ? 'On' : 'Off',
              ),
              _ValueRow('Protocol', vpnProtocolLabel(vpn.protocol)),
              _ValueRow('Release scope', releaseTruth.releaseLabel),
              _ValueRow('Runtime status', releaseTruth.runtimeStatus),
              const SizedBox(height: 8),
              const _RuntimeSetupPanel(),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _GroupedSection(
          title: 'Usage',
          child: plan.when(
            data: (value) => _UsageSummary(
              plan: value,
              vpn: vpn,
              showMonthlyUsage: !config.useMockApi,
            ),
            loading: () => const _LoadingLine('Loading usage'),
            error: (_, __) => const _InlineMessage(
              icon: Icons.warning_amber_rounded,
              message: 'Usage could not be loaded.',
              tone: _Tone.warning,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _GroupedSection(
          title: 'Actions',
          child: Column(
            children: [
              _ActionRow(
                icon: Icons.receipt_long_rounded,
                label: 'Open diagnostics',
                onTap: () => _showDiagnostics(context),
              ),
              const SizedBox(height: 8),
              _ActionRow(
                icon: Icons.open_in_new_rounded,
                label: 'Open account portal',
                onTap: () =>
                    ref.read(externalLinksProvider).openUrl(config.portalUrl),
              ),
              const SizedBox(height: 8),
              _ActionRow(
                icon: Icons.logout_rounded,
                label: 'Sign out',
                onTap: () => _signOut(context, ref),
                filled: true,
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
        _InfoRow(
          'VPN state',
          _statusDescriptor(
            vpn,
            simulateTunnel: ref.watch(appConfigProvider).simulateTunnel,
          ).label,
        ),
        _InfoRow('Native bridge',
            service.isNativeAvailable ? 'Available' : 'Unavailable'),
        _InfoRow('Protocol', vpnProtocolLabel(vpn.protocol)),
        _InfoRow(
          'Release scope',
          SecureWaveReleaseTruth.currentPlatform().releaseLabel,
        ),
        _InfoRow(
          'Platform runtime',
          SecureWaveReleaseTruth.currentPlatform().runtimeStatus,
        ),
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
  const _ProtocolPicker({
    required this.selected,
    required this.selectedServerId,
    required this.servers,
  });

  final VpnProtocol selected;
  final String? selectedServerId;
  final List<ServerRegion> servers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnService = ref.watch(vpnServiceProvider);
    final setup = ref.watch(linuxRuntimeInstallStateProvider);
    final openVpnLocalAvailable = setup.maybeWhen(
      data: (value) => value.installed && value.openVpnAvailable,
      orElse: () => false,
    );
    final openVpnBackendAvailable =
        _openVpnBackendAvailable(selectedServerId, servers);
    final openVpnEnabled = vpnService.canConnectProtocol(VpnProtocol.openVpn) &&
        openVpnLocalAvailable &&
        openVpnBackendAvailable;
    final openVpnDetail = !openVpnBackendAvailable
        ? 'Unavailable for the selected region.'
        : (!openVpnLocalAvailable
            ? 'Install the .deb helper with OpenVPN runtime support.'
            : 'Backend profile and local runtime are available.');
    return Column(
      children: [
        _ProtocolTile(
          protocol: VpnProtocol.wireGuard,
          selected: selected == VpnProtocol.wireGuard,
          title: 'WireGuard',
          detail: 'Primary Linux runtime path.',
          enabled: vpnService.canConnectProtocol(VpnProtocol.wireGuard),
        ),
        const SizedBox(height: 8),
        _ProtocolTile(
          protocol: VpnProtocol.openVpn,
          selected: selected == VpnProtocol.openVpn,
          title: 'OpenVPN',
          detail: openVpnDetail,
          enabled: openVpnEnabled,
        ),
        const SizedBox(height: 8),
        _ProtocolTile(
          protocol: VpnProtocol.ikev2,
          selected: selected == VpnProtocol.ikev2,
          title: 'IKEv2/IPSec',
          detail: vpnService.protocolUnavailableReason(VpnProtocol.ikev2) ??
              'Requires a backend-issued IKEv2 profile and strongSwan.',
          enabled: vpnService.canConnectProtocol(VpnProtocol.ikev2),
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
  const _ConnectionStrip({
    required this.status,
    required this.protocol,
    required this.server,
    required this.desiredOn,
  });

  final _StatusDescriptor status;
  final VpnProtocol protocol;
  final String server;
  final bool desiredOn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: status.background,
        border: Border.all(color: status.border),
        borderRadius: BorderRadius.circular(FreshTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(status.icon, color: status.color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  status.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _StatusChip(label: status.shortLabel, tone: status.tone),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: status.border),
          const SizedBox(height: 10),
          _FactRow(
            items: [
              _FactItem('Server', server),
              _FactItem('Protocol', vpnProtocolLabel(protocol)),
              _FactItem('Desired', desiredOn ? 'On' : 'Off'),
            ],
          ),
        ],
      ),
    );
  }
}

class _FactItem {
  const _FactItem(this.label, this.value);

  final String label;
  final String value;
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.items});

  final List<_FactItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 330) {
          return Column(
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: _FactLine(item: item),
                ),
            ],
          );
        }
        return Row(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              Expanded(child: _FactColumn(item: items[index])),
              if (index != items.length - 1)
                Container(
                  width: 1,
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: FreshTheme.line,
                ),
            ],
          ],
        );
      },
    );
  }
}

class _FactColumn extends StatelessWidget {
  const _FactColumn({required this.item});

  final _FactItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 3),
        Text(
          item.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: FreshTheme.graphite,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _FactLine extends StatelessWidget {
  const _FactLine({required this.item});

  final _FactItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: Text(
            item.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: FreshTheme.graphite,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}

class _ConnectionActions extends StatelessWidget {
  const _ConnectionActions({
    required this.connected,
    required this.busy,
    required this.onConnectToggle,
    required this.onDiagnostics,
  });

  final bool connected;
  final bool busy;
  final VoidCallback onConnectToggle;
  final VoidCallback onDiagnostics;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 430;
    final primary = FilledButton.icon(
      onPressed: busy ? null : onConnectToggle,
      icon: Icon(
          connected ? Icons.stop_rounded : Icons.power_settings_new_rounded),
      label: Text(connected ? 'Disconnect' : 'Connect'),
    );
    final secondary = OutlinedButton.icon(
      onPressed: onDiagnostics,
      icon: const Icon(Icons.receipt_long_rounded),
      label: const Text('Diagnostics'),
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          const SizedBox(height: 10),
          secondary,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: primary),
        const SizedBox(width: 10),
        secondary,
      ],
    );
  }
}

class _UsageSummary extends StatelessWidget {
  const _UsageSummary({
    required this.plan,
    required this.vpn,
    required this.showMonthlyUsage,
  });

  final UserPlan plan;
  final VpnState vpn;
  final bool showMonthlyUsage;

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
        _ValueRow('Current session', _sessionUsageText(vpn)),
        _ValueRow('Down rate', formatMbpsFromBytesPerSecond(vpn.dataRateDown)),
        _ValueRow('Up rate', formatMbpsFromBytesPerSecond(vpn.dataRateUp)),
        _ValueRow('Counter source', _counterSourceText(vpn)),
        if (!vpn.sessionCountersAvailable &&
            vpn.sessionUsageUnavailableReason != null) ...[
          const SizedBox(height: 6),
          _InlineMessage(
            icon: Icons.info_outline_rounded,
            message: vpn.sessionUsageUnavailableReason!,
            tone: _Tone.warning,
          ),
        ],
        const SizedBox(height: 12),
        if (!showMonthlyUsage) ...[
          const _InlineMessage(
            icon: Icons.info_outline_rounded,
            message: 'Monthly usage is unavailable in demo mode.',
            tone: _Tone.warning,
          ),
        ] else ...[
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
          _UsageMeter(value: plan.isUnlimited ? 1 : percent),
          const SizedBox(height: 12),
          _ValueRow('Used', '${plan.usedGb.toStringAsFixed(1)} GB'),
          _ValueRow('Cap', cap),
          _ValueRow('Usage', percentText),
        ],
      ],
    );
  }
}

class _UsageMeter extends StatelessWidget {
  const _UsageMeter({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final clamped = value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0;
    return Container(
      key: const ValueKey('usage-meter'),
      height: 10,
      decoration: BoxDecoration(
        color: FreshTheme.surfaceMuted,
        border: Border.all(color: FreshTheme.line),
        borderRadius: BorderRadius.circular(5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: clamped,
          heightFactor: 1,
          child: const ColoredBox(color: FreshTheme.primary),
        ),
      ),
    );
  }
}

String _sessionUsageText(VpnState vpn) {
  if (vpn.sessionCountersAvailable && vpn.sessionUsageReady) {
    return formatBytes(vpn.sessionTotalBytes);
  }
  if (vpn.status == VpnStatus.connected || vpn.status == VpnStatus.connecting) {
    return 'Waiting for counters';
  }
  if (vpn.sessionTotalBytes > 0) {
    return formatBytes(vpn.sessionTotalBytes);
  }
  return 'No active session';
}

String _counterSourceText(VpnState vpn) {
  if (vpn.sessionCountersAvailable) {
    return vpn.sessionCounterInterface ?? 'Tunnel interface';
  }
  if (vpn.status == VpnStatus.connected || vpn.status == VpnStatus.connecting) {
    return 'Unavailable';
  }
  if (vpn.sessionCounterInterface != null) {
    return vpn.sessionCounterInterface!;
  }
  return 'Not connected';
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
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _GroupedSection extends StatelessWidget {
  const _GroupedSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _PlainPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title),
          const SizedBox(height: 12),
          child,
        ],
      ),
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
      trailing: selected
          ? const Icon(Icons.check_rounded, color: FreshTheme.primary)
          : null,
      onTap: onTap,
    );
  }
}

class _AccountSummary extends StatelessWidget {
  const _AccountSummary({required this.account});

  final UserAccount account;

  @override
  Widget build(BuildContext context) {
    final email = account.email.isEmpty ? 'Signed in' : account.email;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FreshTheme.surfaceMuted,
        border: Border.all(color: FreshTheme.line),
        borderRadius: BorderRadius.circular(FreshTheme.radiusSmall),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_circle_outlined,
              size: 28, color: FreshTheme.graphiteMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _StatusChip(
                      label: account.isActive ? 'Active' : 'Inactive',
                      tone: account.isActive ? _Tone.success : _Tone.warning,
                    ),
                    _StatusChip(
                      label: account.emailVerified ? 'Verified' : 'Unverified',
                      tone: account.emailVerified ? _Tone.info : _Tone.warning,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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
    return _ValueRow(label, value);
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelStyle = Theme.of(context).textTheme.bodySmall;
          final valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: FreshTheme.graphite,
                fontWeight: FontWeight.w600,
              );
          if (constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: valueStyle,
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 104,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: valueStyle,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(FreshTheme.radiusSmall),
      child: Opacity(
        opacity: enabled ? 1 : 0.56,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: filled ? FreshTheme.primary : FreshTheme.surfaceMuted,
            border: Border.all(
              color: filled ? FreshTheme.primary : FreshTheme.line,
            ),
            borderRadius: BorderRadius.circular(FreshTheme.radiusSmall),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 19,
                color: filled ? Colors.white : FreshTheme.graphiteMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: filled ? Colors.white : FreshTheme.graphite,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: filled ? Colors.white : FreshTheme.graphiteMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuntimeSetupPanel extends ConsumerStatefulWidget {
  const _RuntimeSetupPanel({
    this.hideWhenInstalled = false,
    this.showLoading = true,
    this.topSpacing = 0,
  });

  final bool hideWhenInstalled;
  final bool showLoading;
  final double topSpacing;

  @override
  ConsumerState<_RuntimeSetupPanel> createState() => _RuntimeSetupPanelState();
}

class _RuntimeSetupPanelState extends ConsumerState<_RuntimeSetupPanel> {
  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(linuxRuntimeInstallStateProvider);
    return setup.when(
      data: (state) {
        if (widget.hideWhenInstalled && !state.supported) {
          return const SizedBox.shrink();
        }
        if (widget.hideWhenInstalled && state.installed) {
          return const SizedBox.shrink();
        }
        final tone = state.installed
            ? _Tone.success
            : state.payloadAvailable
                ? _Tone.warning
                : _Tone.error;
        final content = Column(
          children: [
            _InlineMessage(
              icon: state.installed
                  ? Icons.verified_rounded
                  : Icons.admin_panel_settings_outlined,
              message: state.message,
              tone: tone,
            ),
            const SizedBox(height: 8),
            _ValueRow(
              'Helper contract',
              state.installedContract <= 0
                  ? 'Not installed'
                  : '${state.installedContract}/${state.requiredContract}',
            ),
            const SizedBox(height: 8),
            _ActionRow(
              icon: Icons.refresh_rounded,
              label: 'Refresh runtime status',
              enabled: true,
              onTap: () {
                ref.invalidate(linuxRuntimeInstallStateProvider);
                ref.invalidate(nativeRuntimeStatusProvider);
              },
            ),
          ],
        );
        if (widget.topSpacing <= 0) return content;
        return Padding(
          padding: EdgeInsets.only(top: widget.topSpacing),
          child: content,
        );
      },
      loading: () {
        if (!widget.showLoading) return const SizedBox.shrink();
        const content = _LoadingLine('Checking runtime setup');
        if (widget.topSpacing <= 0) return content;
        return Padding(
          padding: EdgeInsets.only(top: widget.topSpacing),
          child: content,
        );
      },
      error: (error, _) => _InlineMessage(
        icon: Icons.warning_amber_rounded,
        message: ApiError.messageFrom(
          error,
          fallback: 'Runtime setup could not be checked.',
        ),
        tone: _Tone.warning,
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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

class _PlatformTruthNotice extends StatelessWidget {
  const _PlatformTruthNotice({required this.truth});

  final PlatformReleaseTruth truth;

  @override
  Widget build(BuildContext context) {
    final tone = truth.isPublicRuntime ? _Tone.success : _Tone.warning;
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
          Icon(
            truth.isPublicRuntime
                ? Icons.verified_user_rounded
                : Icons.devices_other_rounded,
            size: 18,
            color: colors.foreground,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      truth.platformName,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: FreshTheme.graphite),
                    ),
                    _StatusChip(label: truth.runtimeStatus, tone: tone),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  truth.summary,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colors.foreground),
                ),
              ],
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
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
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

_StatusDescriptor _statusDescriptor(
  VpnState vpn, {
  bool simulateTunnel = false,
}) {
  final backendUnreachable = vpn.status == VpnStatus.error &&
      vpn.errorKind == VpnErrorKind.backendUnreachable;
  return switch (vpn.status) {
    VpnStatus.connected => _StatusDescriptor(
        label: simulateTunnel ? 'Simulated (not encrypted)' : 'VPN connected',
        shortLabel: simulateTunnel ? 'Demo' : 'On',
        icon: Icons.verified_rounded,
        color: FreshTheme.primary,
        background: FreshTheme.primarySoft,
        border: const Color(0xFF2F61A6),
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

bool _openVpnBackendAvailable(
  String? selectedServerId,
  List<ServerRegion> servers,
) {
  if (selectedServerId != null) {
    for (final server in servers) {
      if (server.id == selectedServerId) {
        return server.explicitlySupportsProtocol('openvpn');
      }
    }
    return false;
  }
  return servers.any((server) => server.explicitlySupportsProtocol('openvpn'));
}

String _serverSubtitle(ServerRegion server) {
  final parts = <String>[];
  if (server.city != null && server.city!.isNotEmpty) parts.add(server.city!);
  if (server.country != null && server.country!.isNotEmpty) {
    parts.add(server.country!);
  }
  if (server.latencyMs != null) parts.add('${server.latencyMs} ms');
  if (server.loadPercent != null) {
    parts.add('${server.loadPercent!.round()}% load');
  }
  final protocols = server.supportedProtocols
      .map((item) => switch (item) {
            'wireguard' => 'WG',
            'openvpn' => 'OVPN',
            'ikev2' => 'IKEv2',
            _ => item,
          })
      .join('/');
  if (protocols.isNotEmpty) parts.add(protocols);
  final health = server.regionHealthStatus ?? server.healthStatus;
  if (health != null && health.isNotEmpty && health != 'up') {
    parts.add(health);
  }
  if (server.premiumOnly) parts.add('Premium');
  return parts.isEmpty ? 'Region endpoint' : parts.join(' · ');
}

Future<void> _signOut(BuildContext context, WidgetRef ref) async {
  final vpn = ref.read(vpnStateProvider);
  if (vpn.status == VpnStatus.connected || vpn.status == VpnStatus.connecting) {
    await ref.read(vpnStateProvider.notifier).disconnect();
  }
  await SecureStorage().clearVpnRuntimeState();
  await ref.read(authSessionProvider).clearSession();
  ref.read(vpnStateProvider.notifier).selectServer(null);
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

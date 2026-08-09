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
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                    _register ? 'Create your SecureWave account' : 'Welcome back',
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
                  _Panel(
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
                              decoration: const InputDecoration(labelText: 'Email'),
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
                                _register ? AutofillHints.newPassword : AutofillHints.password,
                              ],
                              textInputAction: _register ? TextInputAction.next : TextInputAction.done,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                suffixIcon: IconButton(
                                  tooltip: _hidePassword ? 'Show password' : 'Hide password',
                                  onPressed: () => setState(() => _hidePassword = !_hidePassword),
                                  icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                ),
                              ),
                              validator: (value) => value == null || value.length < 8
                                  ? 'Use at least 8 characters.'
                                  : null,
                            ),
                            if (_register) ...[
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _confirm,
                                obscureText: true,
                                decoration: const InputDecoration(labelText: 'Confirm password'),
                                validator: (value) => value != _password.text ? 'Passwords do not match.' : null,
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              _Message(text: _error!, error: true),
                            ],
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Text(_register ? 'Create account' : 'Sign in'),
                            ),
                            const SizedBox(height: 6),
                            TextButton(
                              onPressed: _busy ? null : () => setState(() {
                                _register = !_register;
                                _error = null;
                              }),
                              child: Text(_register ? 'Use an existing account' : 'Create a new account'),
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
        await auth.register(email: _email.text.trim(), password: _password.text);
      } else {
        await auth.login(email: _email.text.trim(), password: _password.text);
      }
      ref.invalidate(currentUserProvider);
      ref.invalidate(targetProvider);
    } catch (error, stackTrace) {
      debugPrint('SecureWave auth failed: $error\n$stackTrace');
      if (mounted) {
        setState(() => _error = ApiError.messageFrom(error, fallback: 'Authentication failed. Check your details and try again.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _HomeView extends ConsumerWidget {
  const _HomeView({required this.isDemo});

  final bool isDemo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final vpn = ref.watch(vpnStateProvider);
    final target = ref.watch(targetProvider);
    final session = ref.read(authSessionProvider);
    final compact = MediaQuery.sizeOf(context).width < 760;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: compact ? 16 : 28,
        title: const _BrandMark(compact: true),
        actions: [
          user.maybeWhen(
            data: (value) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: Text(value.email, overflow: TextOverflow.ellipsis)),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await ref.read(authServiceProvider).logout();
              ref.invalidate(currentUserProvider);
            },
            icon: const Icon(Icons.logout_outlined),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(compact ? 16 : 28, 28, compact ? 16 : 28, 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
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
                    onConnect: () => unawaited(ref.read(vpnStateProvider.notifier).connect()),
                    onDisconnect: () => unawaited(ref.read(vpnStateProvider.notifier).disconnect()),
                  ),
                  const SizedBox(height: 16),
                  _DetailsRow(vpn: vpn, target: target),
                  if (vpn.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    _Message(text: vpn.errorMessage!, error: true),
                  ],
                  const SizedBox(height: 24),
                  Text('Account', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    session.accessToken == null ? 'Signed out' : 'Session stored securely on this device.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
        Text(connected ? 'Protected' : 'Private internet, one tap away', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          isDemo ? 'A deterministic simulated WireGuard experience.' : 'A real WireGuard tunnel to SecureWave Beta.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.vpn, required this.target, required this.onConnect, required this.onDisconnect});

  final VpnState vpn;
  final AsyncValue<SecureWaveTarget> target;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final busy = vpn.status == VpnStatus.connecting || vpn.status == VpnStatus.disconnecting;
    final connected = vpn.status == VpnStatus.connected;
    final statusLabel = switch (vpn.status) {
      VpnStatus.disconnected => 'Disconnected',
      VpnStatus.connecting => 'Connecting',
      VpnStatus.connected => 'Connected',
      VpnStatus.disconnecting => 'Disconnecting',
      VpnStatus.error => 'Connection error',
    };
    final targetLabel = target.maybeWhen(data: (value) => value.name, orElse: () => 'SecureWave Beta');
    return _Panel(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: connected ? AppUIv1.green : AppUIv1.graphiteMuted, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Text(statusLabel, style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 58,
            child: FilledButton.icon(
              onPressed: busy ? null : connected ? onDisconnect : onConnect,
              icon: Icon(connected ? Icons.stop_circle_outlined : Icons.power_settings_new_rounded),
              label: Text(connected ? 'Disconnect' : 'Connect'),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Icon(Icons.shield_outlined, size: 18),
              const SizedBox(width: 8),
              Text('WireGuard', style: Theme.of(context).textTheme.bodyMedium),
              const Spacer(),
              Text(targetLabel, style: Theme.of(context).textTheme.bodyMedium),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _Detail(label: 'Connection health', value: vpn.healthLabel, icon: Icons.favorite_border_rounded)),
        const SizedBox(width: 12),
        Expanded(child: _Detail(label: 'Session usage', value: '${_formatBytes(vpn.rxBytes + vpn.txBytes)} transferred', icon: Icons.swap_vert_rounded)),
      ],
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
    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppUIv1.primary),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 4), Text(value, style: Theme.of(context).textTheme.titleMedium)])),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(18)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppUIv1.surface,
        border: Border.all(color: AppUIv1.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(padding: padding, child: child),
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
        Container(width: compact ? 26 : 34, height: compact ? 26 : 34, decoration: BoxDecoration(color: AppUIv1.primary, borderRadius: BorderRadius.circular(7)), child: Icon(Icons.waves_rounded, color: Colors.white, size: compact ? 17 : 22)),
        const SizedBox(width: 10),
        Text('SecureWave', style: (compact ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.headlineMedium)?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppUIv1.amberSoft, border: Border.all(color: AppUIv1.amber), borderRadius: BorderRadius.circular(8)),
      child: const Row(children: [Icon(Icons.science_outlined, size: 18, color: AppUIv1.amber), SizedBox(width: 8), Expanded(child: Text('DEMO MODE · Simulated connection only', style: TextStyle(color: AppUIv1.amber, fontWeight: FontWeight.w700)))]),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? AppUIv1.red : AppUIv1.amber;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: error ? AppUIv1.redSoft : AppUIv1.amberSoft, border: Border.all(color: color), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [Icon(error ? Icons.error_outline : Icons.info_outline, color: color, size: 18), const SizedBox(width: 9), Expanded(child: Text(text, style: TextStyle(color: color)))]),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

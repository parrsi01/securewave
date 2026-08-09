// WireGuard-only Linux smoke runner used by the real-beta acceptance script.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/models/vpn_status.dart';
import 'core/services/secure_storage.dart';
import 'core/state/vpn_state.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: _ProbeApp()));
}

class _ProbeApp extends ConsumerStatefulWidget {
  const _ProbeApp();

  @override
  ConsumerState<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends ConsumerState<_ProbeApp> {
  final _clock = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  Widget build(BuildContext context) => const MaterialApp(home: Scaffold(body: Center(child: Text('SecureWave WireGuard smoke running'))));

  Future<void> _run() async {
    try {
      final env = Platform.environment;
      final email = env['SECUREWAVE_RUNTIME_PROBE_EMAIL']?.trim() ?? '';
      final password = env['SECUREWAVE_RUNTIME_PROBE_PASSWORD'] ?? '';
      if (email.isEmpty || password.isEmpty) throw StateError('SECUREWAVE_RUNTIME_PROBE_EMAIL and SECUREWAVE_RUNTIME_PROBE_PASSWORD are required.');
      final holdSeconds = int.tryParse(env['SECUREWAVE_RUNTIME_PROBE_HOLD_SECONDS'] ?? '20');
      if (holdSeconds == null || holdSeconds < 1) throw StateError('SECUREWAVE_RUNTIME_PROBE_HOLD_SECONDS must be positive.');

      await SecureStorage().clearVpnRuntimeState();
      await ref.read(authServiceProvider).login(email: email, password: password);
      final notifier = ref.read(vpnStateProvider.notifier);
      await notifier.connect();
      final connected = ref.read(vpnStateProvider);
      _event('connect_result', connected);
      if (connected.status != VpnStatus.connected) throw StateError('WireGuard did not connect.');
      await Future<void>.delayed(Duration(seconds: holdSeconds));
      await notifier.disconnect();
      final disconnected = ref.read(vpnStateProvider);
      _event('disconnect_result', disconnected);
      if (disconnected.status != VpnStatus.disconnected) throw StateError('WireGuard did not disconnect cleanly.');
      exitCode = 0;
      exit(0);
    } catch (error, stackTrace) {
      stdout.writeln(jsonEncode({'event': 'runtime_probe_error', 'error': error.toString(), 'stack': stackTrace.toString(), 'elapsed_ms': _clock.elapsedMilliseconds}));
      exitCode = 1;
      exit(1);
    }
  }

  void _event(String event, VpnState state) {
    stdout.writeln(jsonEncode({'event': event, 'status': state.status.name, 'health': state.healthLabel, 'rx_bytes': state.rxBytes, 'tx_bytes': state.txBytes, 'error': state.errorMessage, 'elapsed_ms': _clock.elapsedMilliseconds}));
  }
}

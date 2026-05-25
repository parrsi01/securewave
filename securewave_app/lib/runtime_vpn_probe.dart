import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/models/vpn_protocol.dart';
import 'core/models/vpn_status.dart';
import 'core/state/vpn_state.dart';
import 'services/auth_service.dart';

const _email = String.fromEnvironment('SECUREWAVE_RUNTIME_PROBE_EMAIL');
const _password = String.fromEnvironment('SECUREWAVE_RUNTIME_PROBE_PASSWORD');
const _protocol = String.fromEnvironment(
  'SECUREWAVE_RUNTIME_PROBE_PROTOCOL',
  defaultValue: 'wireguard',
);
const _serverId = String.fromEnvironment('SECUREWAVE_RUNTIME_PROBE_SERVER_ID');
const _holdSeconds = int.fromEnvironment(
  'SECUREWAVE_RUNTIME_PROBE_HOLD_SECONDS',
  defaultValue: 20,
);
const _disconnectAfter = bool.fromEnvironment(
  'SECUREWAVE_RUNTIME_PROBE_DISCONNECT_AFTER',
  defaultValue: true,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await AppConfig.load();
  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWith((_) => config),
      ],
      child: const _RuntimeProbeApp(),
    ),
  );
}

class _RuntimeProbeApp extends ConsumerStatefulWidget {
  const _RuntimeProbeApp();

  @override
  ConsumerState<_RuntimeProbeApp> createState() => _RuntimeProbeAppState();
}

class _RuntimeProbeAppState extends ConsumerState<_RuntimeProbeApp> {
  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('SecureWave runtime probe running')),
      ),
    );
  }

  Future<void> _run() async {
    try {
      if (_email.trim().isEmpty || _password.trim().isEmpty) {
        throw StateError(
          'SECUREWAVE_RUNTIME_PROBE_EMAIL and '
          'SECUREWAVE_RUNTIME_PROBE_PASSWORD are required.',
        );
      }

      final protocol = vpnProtocolFromStorage(_protocol);
      final auth = ref.read(authServiceProvider);
      await auth.login(email: _email, password: _password);

      final notifier = ref.read(vpnStateProvider.notifier);
      await notifier.selectProtocol(protocol);
      if (_serverId.trim().isNotEmpty) {
        notifier.selectServer(_serverId.trim());
      }

      await notifier.connect();
      final connectedState = ref.read(vpnStateProvider);
      _printProbeEvent('connect_result', connectedState);
      if (connectedState.status != VpnStatus.connected) {
        exitCode = 1;
        exit(1);
      }

      if (_holdSeconds > 0) {
        _printMessage({
          'event': 'holding_for_evidence',
          'hold_seconds': _holdSeconds,
          'protocol': vpnProtocolStorageValue(protocol),
        });
        await Future<void>.delayed(const Duration(seconds: _holdSeconds));
      }

      if (_disconnectAfter) {
        await notifier.disconnect();
        _printProbeEvent('disconnect_result', ref.read(vpnStateProvider));
      }
      exitCode = 0;
      exit(0);
    } catch (error, stackTrace) {
      _printMessage({
        'event': 'runtime_probe_error',
        'error': error.toString(),
        'stack': stackTrace.toString(),
      });
      exitCode = 1;
      exit(1);
    }
  }

  void _printProbeEvent(String event, VpnState state) {
    _printMessage({
      'event': event,
      'status': state.status.name,
      'protocol': vpnProtocolStorageValue(state.protocol),
      'selected_server_id': state.selectedServerId,
      'error_kind': state.errorKind?.name,
      'error_message': state.errorMessage,
      'last_profile_fetch_ok': state.lastProfileFetchOk,
      'last_tunnel_start_ok': state.lastTunnelStartOk,
    });
  }

  void _printMessage(Map<String, Object?> payload) {
    stdout.writeln(jsonEncode(payload));
  }
}

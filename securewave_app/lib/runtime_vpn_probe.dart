import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/models/vpn_protocol.dart';
import 'core/models/vpn_status.dart';
import 'core/services/secure_storage.dart';
import 'core/state/vpn_state.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final defaults = AppConfig.defaults();
  final environment = Platform.environment;
  final apiBase = environment['SECUREWAVE_API_BASE_URL']?.trim();
  final config = AppConfig(
    apiBaseUrl:
        apiBase == null || apiBase.isEmpty ? defaults.apiBaseUrl : apiBase,
    portalUrl: defaults.portalUrl,
    upgradeUrl: defaults.upgradeUrl,
    useMockApi: _environmentBool(
      environment,
      'SECUREWAVE_USE_MOCK_API',
      defaults.useMockApi,
    ),
    resetSessionOnBoot: false,
  );
  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWith((_) => config),
      ],
      child: const _RuntimeProbeApp(),
    ),
  );
}

bool _environmentBool(
  Map<String, String> environment,
  String name,
  bool fallback,
) {
  final value = environment[name]?.trim().toLowerCase();
  if (value == null || value.isEmpty) return fallback;
  if (value == 'true' || value == '1' || value == 'yes') return true;
  if (value == 'false' || value == '0' || value == 'no') return false;
  throw StateError('$name must be true or false.');
}

class _RuntimeProbeApp extends ConsumerStatefulWidget {
  const _RuntimeProbeApp();

  @override
  ConsumerState<_RuntimeProbeApp> createState() => _RuntimeProbeAppState();
}

class _RuntimeProbeAppState extends ConsumerState<_RuntimeProbeApp> {
  final Stopwatch _probeClock = Stopwatch()..start();

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
      final environment = Platform.environment;
      final email = environment['SECUREWAVE_RUNTIME_PROBE_EMAIL']?.trim() ?? '';
      final password =
          environment['SECUREWAVE_RUNTIME_PROBE_PASSWORD']?.trim() ?? '';
      if (email.isEmpty || password.isEmpty) {
        throw StateError(
          'SECUREWAVE_RUNTIME_PROBE_EMAIL and '
          'SECUREWAVE_RUNTIME_PROBE_PASSWORD are required.',
        );
      }

      final protocolName =
          environment['SECUREWAVE_RUNTIME_PROBE_PROTOCOL']?.trim() ??
              'wireguard';
      final protocol = vpnProtocolFromStorage(protocolName);
      if (vpnProtocolStorageValue(protocol) != protocolName.toLowerCase()) {
        throw StateError(
          'SECUREWAVE_RUNTIME_PROBE_PROTOCOL must be wireguard, openvpn, or ikev2.',
        );
      }
      final authMode = environment['SECUREWAVE_RUNTIME_PROBE_AUTH_MODE']
              ?.trim()
              .toLowerCase() ??
          'login';
      final holdSeconds = int.tryParse(
        environment['SECUREWAVE_RUNTIME_PROBE_HOLD_SECONDS'] ?? '20',
      );
      if (holdSeconds == null || holdSeconds <= 0) {
        throw StateError(
          'SECUREWAVE_RUNTIME_PROBE_HOLD_SECONDS must be a positive integer.',
        );
      }
      final disconnectAfter = _environmentBool(
        environment,
        'SECUREWAVE_RUNTIME_PROBE_DISCONNECT_AFTER',
        true,
      );
      if (!disconnectAfter) {
        throw StateError(
          'SECUREWAVE_RUNTIME_PROBE_DISCONNECT_AFTER must remain true for proof runs.',
        );
      }

      final allowUnadvertisedOpenVpnCertification = _environmentBool(
        environment,
        'SECUREWAVE_RUNTIME_PROBE_ALLOW_UNADVERTISED_OPENVPN',
        false,
      );

      final resetRuntimeReferences = _environmentBool(
        environment,
        'SECUREWAVE_RUNTIME_PROBE_RESET_REFERENCES',
        true,
      );
      if (resetRuntimeReferences) {
        // The probe is an isolated, fresh-profile certification run. Clear
        // stale device/server/profile references left by earlier installs so
        // it deterministically exercises backend device recovery instead of
        // failing on an obsolete identifier from the desktop keyring.
        await SecureStorage().clearVpnRuntimeState();
      }

      final auth = ref.read(authServiceProvider);
      if (authMode != 'login') {
        throw StateError(
          'SECUREWAVE_RUNTIME_PROBE_AUTH_MODE must remain login for certification.',
        );
      }
      await auth.login(email: email, password: password);

      final notifier = ref.read(vpnStateProvider.notifier);
      await notifier.ensureInitialized();
      await notifier.selectProtocol(protocol);
      final serverId =
          environment['SECUREWAVE_RUNTIME_PROBE_SERVER_ID']?.trim() ?? '';
      if (serverId.isNotEmpty) {
        notifier.selectServer(serverId);
      }

      await notifier.connect(
        allowUnadvertisedOpenVpnCertification:
            allowUnadvertisedOpenVpnCertification,
      );
      final connectedState = ref.read(vpnStateProvider);
      _printProbeEvent('connect_result', connectedState);
      if (connectedState.status != VpnStatus.connected ||
          connectedState.protocol != protocol ||
          connectedState.lastProfileFetchOk != true ||
          connectedState.lastTunnelStartOk != true) {
        throw StateError(
          'Connect proof did not confirm the requested protocol, a fresh profile, '
          'and a successful tunnel start.',
        );
      }

      _printMessage({
        'event': 'holding_for_evidence',
        'hold_seconds': holdSeconds,
        'protocol': vpnProtocolStorageValue(protocol),
      });
      await stdout.flush();
      await Future<void>.delayed(Duration(seconds: holdSeconds));

      await notifier.disconnect();
      final disconnectedState = ref.read(vpnStateProvider);
      _printProbeEvent('disconnect_result', disconnectedState);
      if (disconnectedState.status != VpnStatus.disconnected) {
        throw StateError('Disconnect proof did not reach disconnected state.');
      }
      await stdout.flush();
      exitCode = 0;
      exit(0);
    } catch (error, stackTrace) {
      _printMessage({
        'event': 'runtime_probe_error',
        'error': error.toString(),
        'stack': stackTrace.toString(),
      });
      await stdout.flush();
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
    stdout.writeln(jsonEncode({
      ...payload,
      'probe_elapsed_ms': _probeClock.elapsedMilliseconds,
    }));
  }
}

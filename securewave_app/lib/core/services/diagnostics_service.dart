import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api_client.dart';
import '../config/app_config.dart';
import '../logging/app_logger.dart';
import '../models/diagnostics.dart';
import '../models/tunnel_health_snapshot.dart';
import '../models/vpn_status.dart';
import '../state/vpn_state.dart';
import 'auth_session.dart';
import 'traffic_stats_service.dart';
import 'tunnel_status_service.dart';
import 'vm_environment.dart';

final diagnosticsServiceProvider = Provider<DiagnosticsService>((ref) {
  return DiagnosticsService(ref);
});

class DiagnosticsService {
  DiagnosticsService(this._ref);

  final Ref _ref;

  Future<List<DiagnosticResult>> run() async {
    final ApiClient api = _ref.read(apiClientProvider);
    final AuthSession auth = _ref.read(authSessionProvider);
    final VpnState vpnState = _ref.read(vpnStateProvider);
    final VmEnvironment vmEnvironment = _ref.read(vmEnvironmentProvider);
    final TunnelHealthSnapshot tunnelSnapshot =
        await _ref.read(tunnelStatusServiceProvider).getStatus();

    final List<DiagnosticResult> results = <DiagnosticResult>[];

    results.add(await _runCheck(
      key: 'BACKEND_OK',
      label: 'Backend reachability',
      action: () async {
        await api.healthCheck();
        return 'Health endpoint reachable.';
      },
    ));

    results.add(await _runCheck(
      key: 'AUTH_OK',
      label: 'Authentication validity',
      action: () async {
        if (!auth.isAuthenticated || (auth.accessToken?.isEmpty ?? true)) {
          throw const _DiagnosticFailure(
              'No active session token. Sign in again.');
        }
        return 'Access token is present.';
      },
    ));

    results.add(await _runCheck(
      key: 'SERVERS_LOADED',
      label: 'Server discovery',
      action: () async {
        final servers = await api.fetchServers(forceRefresh: true);
        if (servers.isEmpty) {
          throw const _DiagnosticFailure('Server list is empty.');
        }
        return '${servers.length} servers available.';
      },
    ));

    results.add(await _runCheck(
      key: 'PROFILE_READY',
      label: 'Profile generation',
      action: () async {
        final String? serverId = vpnState.selectedServerId;
        if (serverId == null || serverId.isEmpty) {
          throw const _DiagnosticFailure('No selected server.');
        }
        final String profile = await api.fetchVpnProfile(serverId: serverId);
        if (profile.trim().isEmpty) {
          throw const _DiagnosticFailure('Profile payload is empty.');
        }
        return 'Profile fetched for $serverId.';
      },
    ));

    results.add(await _runCheck(
      key: 'TUNNEL_INTERFACE_OK',
      label: 'Tunnel interface',
      action: () async {
        if (tunnelSnapshot.interfaceOk) {
          return 'Tunnel interface ${tunnelSnapshot.interfaceName ?? 'detected'} is available.';
        }
        throw _DiagnosticFailure(
          vpnState.status == VpnStatus.connected
              ? 'Tunnel interface missing while connected.'
              : 'Tunnel interface is not active.',
        );
      },
    ));

    results.add(await _runCheck(
      key: 'ROUTING_OK',
      label: 'Routing validation',
      action: () async {
        if (vmEnvironment.safeModeEnabled && !tunnelSnapshot.routingOk) {
          return 'VM safe mode enabled; routing validation deferred.';
        }
        if (tunnelSnapshot.routingOk) {
          return 'Default route points at ${tunnelSnapshot.interfaceName ?? 'the tunnel interface'}.';
        }
        throw const _DiagnosticFailure(
            'Default route is not using the active tunnel.');
      },
    ));

    results.add(await _runCheck(
      key: 'DNS_OK',
      label: 'DNS validation',
      action: () async {
        final uri = Uri.parse(_ref.read(appConfigProvider).apiBaseUrl);
        final host = uri.host.isEmpty ? 'securewave.ai' : uri.host;
        final resolved = await InternetAddress.lookup(host);
        if (resolved.isEmpty) {
          throw const _DiagnosticFailure('DNS resolution returned no records.');
        }
        return 'Resolved $host to ${resolved.first.address}.';
      },
    ));

    results.add(await _runCheck(
      key: 'TRAFFIC_FLOWING',
      label: 'Traffic probe',
      action: () async {
        if (vpnState.status != VpnStatus.connected) {
          throw const _DiagnosticFailure(
              'Connect the tunnel before running traffic validation.');
        }
        final before = await _ref.read(trafficStatsServiceProvider).sample();
        final stopwatch = Stopwatch()..start();
        final response = await Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
          responseType: ResponseType.plain,
        )).get<String>('https://1.1.1.1/cdn-cgi/trace');
        stopwatch.stop();
        final after = await _ref.read(trafficStatsServiceProvider).sample();
        final deltaRx = after.receivedBytes - before.receivedBytes;
        final deltaTx = after.transmittedBytes - before.transmittedBytes;
        if ((response.data ?? '').isEmpty || (deltaRx <= 0 && deltaTx <= 0)) {
          throw const _DiagnosticFailure(
              'HTTP probe completed but traffic counters did not advance.');
        }
        AppLogger.diagnostics(
          'traffic_probe_complete',
          fields: <String, Object?>{
            'latency_ms': stopwatch.elapsedMilliseconds,
            'rx_delta': deltaRx,
            'tx_delta': deltaTx,
          },
        );
        return 'Traffic flowing with ${stopwatch.elapsedMilliseconds}ms latency.';
      },
    ));

    return results;
  }

  Future<DiagnosticResult> _runCheck({
    required String key,
    required String label,
    required Future<String> Function() action,
  }) async {
    try {
      final message = await action();
      AppLogger.diagnostics('check_ok',
          fields: <String, Object?>{'key': key, 'message': message});
      return DiagnosticResult(
        key: key,
        label: label,
        status: DiagnosticStatus.ok,
        message: message,
      );
    } on _DiagnosticFailure catch (error) {
      AppLogger.warning(
        'check_failed',
        category: AppLogCategory.diagnostics,
        fields: <String, Object?>{'key': key, 'message': error.message},
      );
      return DiagnosticResult(
        key: key,
        label: label,
        status: DiagnosticStatus.failed,
        message: error.message,
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'diagnostics_check_failed',
        error: error,
        stackTrace: stackTrace,
        category: AppLogCategory.diagnostics,
        fields: <String, Object?>{'key': key},
      );
      return DiagnosticResult(
        key: key,
        label: label,
        status: DiagnosticStatus.failed,
        message: 'Check failed: $error',
      );
    }
  }
}

class _DiagnosticFailure implements Exception {
  const _DiagnosticFailure(this.message);

  final String message;
}

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api_client.dart';
import '../config/app_config.dart';
import '../logging/app_logger.dart';
import '../models/diagnostics.dart';
import '../models/tunnel_health_snapshot.dart';
import '../models/vpn_status.dart';
import '../state/network_lock_state.dart';
import '../state/vpn_state.dart';
import '../utils/api_error.dart';
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
    final networkLock = _ref.read(networkLockProvider);

    final List<DiagnosticResult> results = <DiagnosticResult>[
      _environmentCheck(
        key: 'VM_SAFE_MODE_ACTIVE',
        label: 'VM safe mode',
        ok: vmEnvironment.safeModeEnabled,
        okMessage: vmEnvironment.reason ??
            'Linux VM safe mode is active. Reconnect pacing and route checks are hardened.',
        failedMessage: 'VM safe mode not required on this device.',
      ),
      _environmentCheck(
        key: vmEnvironment.defaultRoutePresent
            ? 'DEFAULT_ROUTE_OK'
            : 'DEFAULT_ROUTE_MISSING',
        label: 'Default route',
        ok: vmEnvironment.defaultRoutePresent,
        okMessage:
            'Default route via ${vmEnvironment.defaultRouteInterface ?? 'system route'}.',
        failedMessage: 'No default route detected.',
        commands: const <String>[
          'ip route',
          'nmcli connection show',
          'sudo systemctl restart NetworkManager',
        ],
      ),
      _environmentCheck(
        key: 'DOCKER_CONFLICT_DETECTED',
        label: 'Docker bridge conflict',
        ok: !(vmEnvironment.hasDockerBridge &&
            tunnelSnapshot.interfaceOk &&
            !tunnelSnapshot.routingOk),
        okMessage: vmEnvironment.hasDockerBridge
            ? 'Docker bridge present, but no active routing conflict detected.'
            : 'No Docker bridge conflict detected.',
        failedMessage:
            'Docker bridge and VPN tunnel appear to be competing for routing.',
        commands: const <String>[
          'ip addr show docker0',
          'ip route get 1.1.1.1',
          'docker network ls',
        ],
      ),
    ];

    if (networkLock.isLocked) {
      results.add(
        DiagnosticResult(
          key: 'KILL_SWITCH_ACTIVE',
          label: 'Best-effort kill switch',
          status: DiagnosticStatus.retrying,
          message: networkLock.reason ??
              'App network requests are paused until the tunnel reconnects.',
          checkedAt: DateTime.now(),
        ),
      );
    }

    results.add(await _runCheck(
      key: 'BACKEND_OK',
      label: 'Backend reachability',
      action: () async {
        await api.healthCheck();
        return const _CheckOutcome('Health endpoint reachable.');
      },
    ));

    results.add(await _runCheck(
      key: 'AUTH_OK',
      label: 'Authentication validity',
      action: () async {
        if (!auth.isAuthenticated || (auth.accessToken?.isEmpty ?? true)) {
          throw const _DiagnosticFailure(
            'No active session token. Sign in again.',
          );
        }
        return const _CheckOutcome('Access token is present.');
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
        return _CheckOutcome('${servers.length} servers available.');
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
        return _CheckOutcome('Profile fetched for $serverId.');
      },
    ));

    results.add(await _runCheck(
      key: tunnelSnapshot.interfaceOk
          ? 'TUNNEL_INTERFACE_OK'
          : 'TUNNEL_INTERFACE_MISSING',
      label: 'Tunnel interface',
      action: () async {
        if (tunnelSnapshot.interfaceOk) {
          return _CheckOutcome(
            'Tunnel interface ${tunnelSnapshot.interfaceName ?? 'detected'} is available.',
          );
        }
        throw _DiagnosticFailure(
          vpnState.status == VpnStatus.connected
              ? 'Tunnel interface missing while connected.'
              : 'Tunnel interface is not active.',
          commands: _vmCommands(vmEnvironment),
        );
      },
    ));

    results.add(await _runCheck(
      key: 'ROUTING_OK',
      label: 'Routing validation',
      action: () async {
        if (vmEnvironment.safeModeEnabled && !tunnelSnapshot.routingOk) {
          throw _DiagnosticFailure(
            'VM route conflict detected. Default route is not using the tunnel.',
            commands: _vmCommands(vmEnvironment),
          );
        }
        if (tunnelSnapshot.routingOk) {
          return _CheckOutcome(
            'Default route points at ${tunnelSnapshot.interfaceName ?? 'the tunnel interface'}.',
          );
        }
        throw const _DiagnosticFailure(
          'Default route is not using the active tunnel.',
          commands: <String>[
            'ip route get 1.1.1.1',
            'route -n get default',
          ],
        );
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
          throw const _DiagnosticFailure(
            'DNS resolution returned no records.',
            commands: <String>[
              'cat /etc/resolv.conf',
              'nslookup securewave.ai',
            ],
          );
        }
        return _CheckOutcome('Resolved $host to ${resolved.first.address}.');
      },
    ));

    results.add(await _runCheck(
      key: 'TRAFFIC_FLOWING',
      label: 'Traffic probe',
      action: () async {
        if (vpnState.status != VpnStatus.connected) {
          throw const _DiagnosticFailure(
            'Connect the tunnel before running traffic validation.',
          );
        }
        final before = await _ref.read(trafficStatsServiceProvider).sample(
              preferredInterface: tunnelSnapshot.interfaceName,
            );
        final stopwatch = Stopwatch()..start();
        final response = await Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 6),
            receiveTimeout: const Duration(seconds: 6),
            responseType: ResponseType.plain,
          ),
        ).get<String>('https://1.1.1.1/cdn-cgi/trace');
        stopwatch.stop();
        final after = await _ref.read(trafficStatsServiceProvider).sample(
              preferredInterface: tunnelSnapshot.interfaceName,
            );
        final deltaRx = after.receivedBytes - before.receivedBytes;
        final deltaTx = after.transmittedBytes - before.transmittedBytes;
        if ((response.data ?? '').isEmpty || (deltaRx <= 0 && deltaTx <= 0)) {
          throw const _DiagnosticFailure(
            'HTTP probe completed but traffic counters did not advance.',
            commands: <String>[
              'curl -I https://1.1.1.1/cdn-cgi/trace',
              'ip route get 1.1.1.1',
            ],
          );
        }
        AppLogger.diagnostics(
          'traffic_probe_complete',
          fields: <String, Object?>{
            'latency_ms': stopwatch.elapsedMilliseconds,
            'rx_delta': deltaRx,
            'tx_delta': deltaTx,
          },
        );
        return _CheckOutcome(
          'Traffic flowing with ${stopwatch.elapsedMilliseconds}ms latency.',
        );
      },
    ));

    return results;
  }

  DiagnosticResult _environmentCheck({
    required String key,
    required String label,
    required bool ok,
    required String okMessage,
    required String failedMessage,
    List<String> commands = const <String>[],
  }) {
    return DiagnosticResult(
      key: key,
      label: label,
      status: ok ? DiagnosticStatus.ok : DiagnosticStatus.failed,
      message: ok ? okMessage : failedMessage,
      commands: ok ? const <String>[] : commands,
      checkedAt: DateTime.now(),
    );
  }

  Future<DiagnosticResult> _runCheck({
    required String key,
    required String label,
    required Future<_CheckOutcome> Function() action,
  }) async {
    try {
      final outcome = await action();
      AppLogger.diagnostics('check_ok',
          fields: <String, Object?>{'key': key, 'message': outcome.message});
      return DiagnosticResult(
        key: key,
        label: label,
        status: DiagnosticStatus.ok,
        message: outcome.message,
        checkedAt: DateTime.now(),
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
        commands: error.commands,
        checkedAt: DateTime.now(),
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
        message: ApiError.messageFrom(
          error,
          fallback: 'Check failed: $error',
        ),
        checkedAt: DateTime.now(),
      );
    }
  }

  List<String> _vmCommands(VmEnvironment vmEnvironment) {
    if (!vmEnvironment.safeModeEnabled) {
      return const <String>[];
    }
    return const <String>[
      'ip route',
      'ip route get 1.1.1.1',
      'nmcli device status',
      'sudo systemctl restart NetworkManager',
      'sudo dhclient -r && sudo dhclient',
    ];
  }
}

class _CheckOutcome {
  const _CheckOutcome(this.message);

  final String message;
}

class _DiagnosticFailure implements Exception {
  const _DiagnosticFailure(this.message, {this.commands = const <String>[]});

  final String message;
  final List<String> commands;
}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/models/vpn_status.dart';
import '../../core/services/auth_session.dart';
import '../../core/services/device_identity.dart';
import '../../core/services/vpn_service.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_ui_v1.dart';
import '../../ui/securewave_ui.dart';

enum _CheckStatus { ok, warn, fail, info }

class _CheckItem {
  const _CheckItem({
    required this.status,
    required this.title,
    required this.message,
  });

  final _CheckStatus status;
  final String title;
  final String message;
}

class ConnectionDiagnosticsSheet extends ConsumerStatefulWidget {
  const ConnectionDiagnosticsSheet({super.key});

  @override
  ConsumerState<ConnectionDiagnosticsSheet> createState() =>
      _ConnectionDiagnosticsSheetState();

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppUIv1.backgroundStrong,
      builder: (context) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.only(top: AppUIv1.space2),
          child: ConnectionDiagnosticsSheet(),
        ),
      ),
    );
  }
}

class _ConnectionDiagnosticsSheetState
    extends ConsumerState<ConnectionDiagnosticsSheet> {
  bool _running = false;
  DateTime? _lastRunAt;
  List<_CheckItem> _items = const [];

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_runChecks);
  }

  String _apiPath(AppConfig config, String path) {
    final base = config.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final normalized = path.startsWith('/') ? path : '/$path';
    if (base.endsWith('/api')) return normalized;
    return '/api$normalized';
  }

  Dio _dioFor(AppConfig config, {String? token}) {
    return Dio(
      BaseOptions(
        baseUrl: config.apiBaseUrl,
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 5),
        headers: <String, String>{
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
      ),
    );
  }

  Future<void> _runChecks() async {
    if (_running) return;
    setState(() => _running = true);

    final config = ref.read(appConfigProvider);
    final session = ref.read(authSessionProvider);
    final vpnService = ref.read(vpnServiceProvider);
    final vpnState = ref.read(vpnStateProvider);

    final token = session.accessToken;
    final isAuthed = token != null && token.isNotEmpty;

    final items = <_CheckItem>[];

    // 1) Backend reachable
    if (config.useMockApi) {
      items.add(
        const _CheckItem(
          status: _CheckStatus.info,
          title: 'Backend reachable',
          message: 'Skipped (mock API enabled).',
        ),
      );
    } else {
      items.add(await _checkHealth(config, token: token));
    }

    // 2) Auth valid
    if (!isAuthed) {
      items.add(
        const _CheckItem(
          status: _CheckStatus.fail,
          title: 'Auth valid',
          message: 'Not signed in.',
        ),
      );
    } else if (config.useMockApi) {
      items.add(
        const _CheckItem(
          status: _CheckStatus.info,
          title: 'Auth valid',
          message: 'Token present (mock mode).',
        ),
      );
    } else {
      items.add(await _checkPlan(config, token: token));
    }

    // 3) Profile fetched
    if (!isAuthed) {
      items.add(
        const _CheckItem(
          status: _CheckStatus.info,
          title: 'Profile fetched',
          message: 'Skipped (not signed in).',
        ),
      );
    } else if (config.useMockApi) {
      items.add(
        const _CheckItem(
          status: _CheckStatus.info,
          title: 'Profile fetched',
          message: 'Simulated (mock mode).',
        ),
      );
    } else {
      items.add(
        await _checkProfile(
          config,
          token: token,
          serverId: vpnState.selectedServerId,
        ),
      );
    }

    // 4) Native tunnel started
    items.add(_checkTunnelStarted(vpnService, vpnState));

    setState(() {
      _items = items;
      _lastRunAt = DateTime.now();
      _running = false;
    });
  }

  Future<_CheckItem> _checkHealth(AppConfig config, {String? token}) async {
    final dio = _dioFor(config, token: token);
    try {
      final resp = await dio.get<Map<String, dynamic>>(
        _apiPath(config, '/health'),
      );
      final status = resp.data?['status']?.toString();
      if (status == 'ok') {
        return const _CheckItem(
          status: _CheckStatus.ok,
          title: 'Backend reachable',
          message: 'OK',
        );
      }
      return const _CheckItem(
        status: _CheckStatus.warn,
        title: 'Backend reachable',
        message: 'Unexpected response.',
      );
    } on DioException catch (e) {
      return _dioFailure('Backend reachable', e);
    } catch (_) {
      return const _CheckItem(
        status: _CheckStatus.fail,
        title: 'Backend reachable',
        message: 'Request failed.',
      );
    }
  }

  Future<_CheckItem> _checkPlan(AppConfig config, {String? token}) async {
    final dio = _dioFor(config, token: token);
    try {
      final resp = await dio.get<Map<String, dynamic>>(
        _apiPath(config, '/user/plan'),
      );
      if (resp.statusCode == 200) {
        return const _CheckItem(
          status: _CheckStatus.ok,
          title: 'Auth valid',
          message: 'OK',
        );
      }
      return _CheckItem(
        status: _CheckStatus.warn,
        title: 'Auth valid',
        message: 'Unexpected status ${resp.statusCode}.',
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        return const _CheckItem(
          status: _CheckStatus.fail,
          title: 'Auth valid',
          message: 'Unauthorized (sign in again).',
        );
      }
      return _dioFailure('Auth valid', e);
    } catch (_) {
      return const _CheckItem(
        status: _CheckStatus.fail,
        title: 'Auth valid',
        message: 'Request failed.',
      );
    }
  }

  Future<_CheckItem> _checkProfile(
    AppConfig config, {
    required String? token,
    String? serverId,
  }) async {
    final dio = _dioFor(config, token: token);
    try {
      final identity = await DeviceIdentity.load();
      final payload = <String, dynamic>{
        'device_name': identity.name,
        'device_type': identity.type,
        'protocol': 'wireguard',
        if (serverId != null) 'server_id': serverId,
      };

      final resp = await dio.post<Map<String, dynamic>>(
        _apiPath(config, '/vpn/profile'),
        data: payload,
      );
      final data = resp.data ?? const <String, dynamic>{};
      final resolvedServerId = data['server_id']?.toString();
      final expiresAt = data['expires_at']?.toString();
      final details = <String>[
        if (resolvedServerId != null && resolvedServerId.isNotEmpty)
          'server=$resolvedServerId',
        if (expiresAt != null && expiresAt.isNotEmpty) 'expires=$expiresAt',
      ].join(' ');
      return _CheckItem(
        status: _CheckStatus.ok,
        title: 'Profile fetched',
        message: details.isEmpty ? 'OK' : 'OK ($details)',
      );
    } on DioException catch (e) {
      return _dioFailure('Profile fetched', e);
    } catch (_) {
      return const _CheckItem(
        status: _CheckStatus.fail,
        title: 'Profile fetched',
        message: 'Request failed.',
      );
    }
  }

  _CheckItem _checkTunnelStarted(VpnService service, VpnState vpnState) {
    if (vpnState.status == VpnStatus.connected) {
      if (service.isNativeAvailable) {
        return const _CheckItem(
          status: _CheckStatus.ok,
          title: 'Native tunnel started',
          message: 'Connected.',
        );
      }
      return const _CheckItem(
        status: _CheckStatus.info,
        title: 'Native tunnel started',
        message: 'Connected (demo tunnel).',
      );
    }
    if (!service.isNativeAvailable) {
      return const _CheckItem(
        status: _CheckStatus.warn,
        title: 'Native tunnel started',
        message: 'Native VPN bridge unavailable on this device.',
      );
    }
    if (vpnState.status == VpnStatus.connecting ||
        vpnState.status == VpnStatus.disconnecting) {
      return const _CheckItem(
        status: _CheckStatus.info,
        title: 'Native tunnel started',
        message: 'In progress…',
      );
    }
    if (vpnState.lastTunnelStartOk == false &&
        vpnState.lastTunnelStartAt != null) {
      return _CheckItem(
        status: _CheckStatus.fail,
        title: 'Native tunnel started',
        message:
            'Last attempt failed (${vpnState.lastTunnelStartAt!.toLocal()}).',
      );
    }
    return const _CheckItem(
      status: _CheckStatus.info,
      title: 'Native tunnel started',
      message: 'Not connected.',
    );
  }

  _CheckItem _dioFailure(String title, DioException e) {
    final status = e.response?.statusCode;
    final message = switch (e.type) {
      DioExceptionType.connectionTimeout => 'Connection timed out.',
      DioExceptionType.receiveTimeout => 'Response timed out.',
      DioExceptionType.connectionError => 'Connection error.',
      DioExceptionType.badResponse =>
        status == null ? 'HTTP error.' : 'HTTP $status',
      DioExceptionType.cancel => 'Cancelled.',
      DioExceptionType.sendTimeout => 'Send timed out.',
      DioExceptionType.badCertificate => 'Bad certificate.',
      DioExceptionType.unknown => 'Request failed.',
    };
    return _CheckItem(
      status: _CheckStatus.fail,
      title: title,
      message: message,
    );
  }

  Color _statusColor(_CheckStatus status) {
    return switch (status) {
      _CheckStatus.ok => AppUIv1.success,
      _CheckStatus.warn => AppUIv1.warning,
      _CheckStatus.fail => AppUIv1.danger,
      _CheckStatus.info => AppUIv1.inkSoft,
    };
  }

  IconData _statusIcon(_CheckStatus status) {
    return switch (status) {
      _CheckStatus.ok => Icons.check_circle,
      _CheckStatus.warn => Icons.warning_amber_rounded,
      _CheckStatus.fail => Icons.error,
      _CheckStatus.info => Icons.info_outline,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppUIv1.space4,
        right: AppUIv1.space4,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppUIv1.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwSectionHeader(
            eyebrow: 'Quick scan',
            title: 'Connection diagnostics',
            subtitle: 'Read-only checks to classify connection issues.',
            trailing: SwStatusPill(
              label: _running ? 'Scanning' : '${_items.length} checks',
              color: _running ? AppUIv1.accentCyan : AppUIv1.accentTeal,
              icon: Icons.monitor_heart_outlined,
              pulse: _running,
            ),
          ),
          const SizedBox(height: AppUIv1.space3),
          if (_running) ...[
            const SwScanBand(),
            const SizedBox(height: AppUIv1.space3),
          ],
          SwPanel(
            accent: AppUIv1.accentCyan,
            child: Column(
              children: [
                for (final item in _items) ...[
                  SwActionTile(
                    icon: _statusIcon(item.status),
                    title: item.title,
                    subtitle: item.message,
                    color: _statusColor(item.status),
                  ),
                  if (item != _items.last)
                    const SizedBox(height: AppUIv1.space3),
                ],
                if (_items.isEmpty)
                  const SwActionTile(
                    icon: Icons.info_outline,
                    title: 'Running checks',
                    subtitle:
                        'SecureWave is collecting local and backend signals.',
                    color: AppUIv1.inkSoft,
                  ),
              ],
            ),
          ),
          if (_lastRunAt != null) ...[
            const SizedBox(height: AppUIv1.space2),
            Text(
              'Last updated: ${_lastRunAt!.toLocal()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: AppUIv1.space3),
          Text(
            'For full logs and advanced actions, use Settings → Run diagnostics.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppUIv1.space3),
        ],
      ),
    );
  }
}

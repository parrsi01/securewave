import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:platform_info/platform_info.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../core/services/auth_session.dart';
import '../../core/services/device_identity.dart';
import '../../core/services/secure_storage.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_ui_v1.dart';
import '../../ui/securewave_ui.dart';

enum _CheckStatus { ok, warn, fail, info }

class _CheckResult {
  const _CheckResult({
    required this.status,
    required this.title,
    required this.message,
    this.details,
  });

  final _CheckStatus status;
  final String title;
  final String message;
  final String? details;
}

class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  bool _running = false;
  DateTime? _lastRunAt;
  final Map<String, _CheckResult> _results = <String, _CheckResult>{};
  String? _runError;

  @override
  void initState() {
    super.initState();
    // Kick off a first pass so users get a quick signal without hunting for the button.
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
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 6),
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
    setState(() {
      _running = true;
      _runError = null;
    });

    final config = ref.read(appConfigProvider);
    final session = ref.read(authSessionProvider);
    final vpnService = ref.read(vpnServiceProvider);
    final vpnState = ref.read(vpnStateProvider);
    final storage = SecureStorage();

    final token = session.accessToken;
    final dio = _dioFor(config, token: token);

    final results = <String, _CheckResult>{};

    // App config (local)
    results['config'] = _CheckResult(
      status: config.useMockApi ? _CheckStatus.warn : _CheckStatus.ok,
      title: 'App configuration',
      message: 'API base: ${config.apiBaseUrl}',
      details: config.useMockApi
          ? 'Mock API is enabled. Set SECUREWAVE_USE_MOCK_API=false in .env for live backend checks.'
          : 'Using live backend endpoints.',
    );

    // Auth (local)
    final isAuthed = token != null && token.isNotEmpty;
    results['auth'] = _CheckResult(
      status: isAuthed ? _CheckStatus.ok : _CheckStatus.fail,
      title: 'Authentication',
      message: isAuthed ? 'Access token present.' : 'Not signed in.',
      details: isAuthed
          ? null
          : 'Sign in to provision a tunnel profile and fetch your plan.',
    );

    // Native tunnel availability (local)
    results['native'] = _CheckResult(
      status: vpnService.isNativeAvailable
          ? _CheckStatus.ok
          : _CheckStatus.warn,
      title: 'Native VPN bridge',
      message: vpnService.isNativeAvailable
          ? 'Available.'
          : 'Unavailable on this device.',
      details: switch (platform.operatingSystem) {
        OperatingSystem.windows =>
          'Windows requires WireGuard for Windows (wireguard.exe). Install it to enable tunneling.',
        OperatingSystem.linux =>
          'Linux requires wg-quick (wireguard-tools). Install it and ensure the app can run elevated commands when prompted.',
        OperatingSystem.macOS =>
          'VPN unavailable on macOS (yet). This build does not include the required Apple Network Extension entitlements.',
        _ => null,
      },
    );

    // Cached profile presence (local)
    try {
      final cachedConfig = await storage.getString(
        SecureStorage.vpnProfileConfigKey,
      );
      final expiresRaw = await storage.getString(
        SecureStorage.vpnProfileExpiresAtKey,
      );
      final expiresAt = expiresRaw != null
          ? DateTime.tryParse(expiresRaw)
          : null;
      results['cache'] = _CheckResult(
        status: (cachedConfig != null && cachedConfig.trim().isNotEmpty)
            ? _CheckStatus.info
            : _CheckStatus.info,
        title: 'Cached tunnel profile',
        message: (cachedConfig != null && cachedConfig.trim().isNotEmpty)
            ? 'Present${expiresAt != null ? ' (expires ${expiresAt.toIso8601String()})' : ''}.'
            : 'No cached profile found.',
      );
    } catch (e) {
      results['cache'] = _CheckResult(
        status: _CheckStatus.warn,
        title: 'Cached tunnel profile',
        message: 'Unable to read secure storage.',
        details: e.toString(),
      );
    }

    // Backend checks (network)
    Future<_CheckResult> checkHealth() async {
      try {
        final resp = await dio.get<Map<String, dynamic>>(
          _apiPath(config, '/health'),
        );
        final data = resp.data ?? const <String, dynamic>{};
        final status = data['status']?.toString();
        if (status == 'ok') {
          return const _CheckResult(
            status: _CheckStatus.ok,
            title: 'Backend health',
            message: 'OK',
          );
        }
        return _CheckResult(
          status: _CheckStatus.warn,
          title: 'Backend health',
          message: 'Unexpected response.',
          details: data.toString(),
        );
      } on DioException catch (e) {
        return _dioFailure('Backend health', e);
      } catch (e) {
        return _CheckResult(
          status: _CheckStatus.fail,
          title: 'Backend health',
          message: 'Request failed.',
          details: e.toString(),
        );
      }
    }

    Future<_CheckResult> checkReady() async {
      try {
        final resp = await dio.get<Map<String, dynamic>>(
          _apiPath(config, '/ready'),
        );
        final data = resp.data ?? const <String, dynamic>{};
        final status = data['status']?.toString();
        if (status == 'ready') {
          return const _CheckResult(
            status: _CheckStatus.ok,
            title: 'Backend readiness',
            message: 'Database connected.',
          );
        }
        return _CheckResult(
          status: _CheckStatus.warn,
          title: 'Backend readiness',
          message: 'Not ready.',
          details: data.toString(),
        );
      } on DioException catch (e) {
        return _dioFailure('Backend readiness', e);
      } catch (e) {
        return _CheckResult(
          status: _CheckStatus.fail,
          title: 'Backend readiness',
          message: 'Request failed.',
          details: e.toString(),
        );
      }
    }

    Future<_CheckResult> checkPlan() async {
      if (!isAuthed) {
        return const _CheckResult(
          status: _CheckStatus.info,
          title: 'Plan lookup',
          message: 'Skipped (not signed in).',
        );
      }
      try {
        final resp = await dio.get<Map<String, dynamic>>(
          _apiPath(config, '/user/plan'),
        );
        if (resp.statusCode == 200) {
          return _CheckResult(
            status: _CheckStatus.ok,
            title: 'Plan lookup',
            message: 'OK',
            details:
                'plan_tier=${resp.data?['plan_tier']} used_gb=${resp.data?['used_gb']}',
          );
        }
        return _CheckResult(
          status: _CheckStatus.warn,
          title: 'Plan lookup',
          message: 'Unexpected status ${resp.statusCode}.',
          details: (resp.data ?? const <String, dynamic>{}).toString(),
        );
      } on DioException catch (e) {
        return _dioFailure('Plan lookup', e);
      } catch (e) {
        return _CheckResult(
          status: _CheckStatus.fail,
          title: 'Plan lookup',
          message: 'Request failed.',
          details: e.toString(),
        );
      }
    }

    Future<_CheckResult> checkProfile() async {
      if (!isAuthed) {
        return const _CheckResult(
          status: _CheckStatus.info,
          title: 'Profile provisioning',
          message: 'Skipped (not signed in).',
        );
      }
      try {
        final identity = await DeviceIdentity.load();

        final payload = <String, dynamic>{
          'device_name': identity.name,
          'device_type': identity.type,
          'protocol': 'wireguard',
          if (vpnState.selectedServerId != null)
            'server_id': vpnState.selectedServerId,
        };

        final resp = await dio.post<Map<String, dynamic>>(
          _apiPath(config, '/vpn/profile'),
          data: payload,
        );
        final data = resp.data ?? const <String, dynamic>{};
        final serverId = data['server_id']?.toString() ?? '';
        final expiresAt = data['expires_at']?.toString();
        final dns = data['dns'] is Map
            ? Map<String, dynamic>.from(data['dns'] as Map)
            : const <String, dynamic>{};
        final dnsServers = dns['servers'] is List
            ? (dns['servers'] as List).length
            : 0;
        final killSwitch = data['kill_switch'] is Map
            ? Map<String, dynamic>.from(data['kill_switch'] as Map)
            : const <String, dynamic>{};
        final ksEnforcement = killSwitch['enforcement']?.toString() ?? '';

        return _CheckResult(
          status: _CheckStatus.ok,
          title: 'Profile provisioning',
          message: 'OK',
          details:
              'server=$serverId expires=$expiresAt dns_servers=$dnsServers kill_switch=$ksEnforcement',
        );
      } on DioException catch (e) {
        return _dioFailure('Profile provisioning', e);
      } catch (e) {
        return _CheckResult(
          status: _CheckStatus.fail,
          title: 'Profile provisioning',
          message: 'Request failed.',
          details: e.toString(),
        );
      }
    }

    final futures = await Future.wait<_CheckResult>([
      checkHealth(),
      checkReady(),
      checkPlan(),
      checkProfile(),
    ]);
    results['health'] = futures[0];
    results['ready'] = futures[1];
    results['plan'] = futures[2];
    results['profile'] = futures[3];

    setState(() {
      _results
        ..clear()
        ..addAll(results);
      _lastRunAt = DateTime.now();
    });

    setState(() => _running = false);
  }

  _CheckResult _dioFailure(String title, DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    final isUnauthorized = status == 401 || status == 403;
    final message = switch (e.type) {
      DioExceptionType.connectionTimeout => 'Connection timed out.',
      DioExceptionType.receiveTimeout => 'Response timed out.',
      DioExceptionType.connectionError => 'Connection error.',
      DioExceptionType.badResponse => 'HTTP $status',
      DioExceptionType.cancel => 'Cancelled.',
      DioExceptionType.sendTimeout => 'Send timed out.',
      DioExceptionType.badCertificate => 'Bad certificate.',
      DioExceptionType.unknown => 'Request failed.',
    };
    return _CheckResult(
      status: isUnauthorized ? _CheckStatus.fail : _CheckStatus.fail,
      title: title,
      message: message,
      details: [
        if (e.message != null) e.message,
        if (data != null) data.toString(),
        if (isUnauthorized)
          'Auth failed. Sign in again, or check that SECUREWAVE_API_BASE_URL points at the correct backend.',
        if (e.type == DioExceptionType.connectionError)
          'If you previously used an Azure URL, it may be offline. Start the backend locally and retry.',
      ].whereType<String>().join('\n'),
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

  String _buildCopyText() {
    final config = ref.read(appConfigProvider);
    final session = ref.read(authSessionProvider);
    final logs = AppLogger.logStream.value;
    final lastLogs = logs.length > 60 ? logs.sublist(logs.length - 60) : logs;

    final lines = <String>[
      'SecureWave Diagnostics',
      'Version: ${AppConstants.appVersion}',
      'Platform: ${platform.operatingSystem.name}',
      'API base: ${config.apiBaseUrl}',
      'Mock API: ${config.useMockApi}',
      'Signed in: ${session.isAuthenticated}',
      if (_lastRunAt != null) 'Last run: ${_lastRunAt!.toIso8601String()}',
      '',
      'Checks:',
      ..._results.entries.map((e) {
        final r = e.value;
        final status = r.status.name.toUpperCase();
        final detail = r.details == null || r.details!.trim().isEmpty
            ? ''
            : '\n  ${r.details}';
        return '- [$status] ${r.title}: ${r.message}$detail';
      }),
      if (_runError != null) '',
      if (_runError != null) 'Run error: $_runError',
      '',
      'Recent logs:',
      ...lastLogs.map((e) => e.toString()),
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final rows = _results.values.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Copy diagnostics',
            onPressed: () async {
              final text = _buildCopyText();
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Diagnostics copied')),
              );
            },
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
      body: SwPage(
        center: false,
        child: ListView(
          children: [
            SwSectionHeader(
              eyebrow: 'Readiness scan',
              title: 'Diagnostics',
              subtitle:
                  'Classifies backend reachability, auth state, profile provisioning, native tunnel availability, and cached profile health.',
              trailing: SwStatusPill(
                label: _running ? 'Scanning' : '${rows.length} checks',
                color: _running ? AppUIv1.accentCyan : AppUIv1.accentTeal,
                icon: _running ? Icons.radar_rounded : Icons.fact_check_rounded,
                pulse: _running,
              ),
            ),
            const SizedBox(height: AppUIv1.space5),
            SwPanel(
              accent: AppUIv1.accentCyan,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 560;
                  final runButton = FilledButton.icon(
                    onPressed: _running ? null : _runChecks,
                    icon: _running
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(_running ? 'Running scan' : 'Run diagnostics'),
                  );
                  final clearButton = OutlinedButton.icon(
                    onPressed: _running
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final storage = SecureStorage();
                            await storage.delete(
                              SecureStorage.vpnProfileConfigKey,
                            );
                            await storage.delete(
                              SecureStorage.vpnProfileExpiresAtKey,
                            );
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Cached profile cleared'),
                              ),
                            );
                            await _runChecks();
                          },
                    icon: const Icon(Icons.cleaning_services_rounded),
                    label: const Text('Clear cache'),
                  );
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        runButton,
                        const SizedBox(height: AppUIv1.space3),
                        clearButton,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: runButton),
                      const SizedBox(width: AppUIv1.space3),
                      clearButton,
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: AppUIv1.space4),
            if (rows.isEmpty)
              const SwPanel(
                child: SwActionTile(
                  icon: Icons.info_outline_rounded,
                  title: 'No results yet',
                  subtitle: 'Tap Run diagnostics to begin.',
                  color: AppUIv1.inkSoft,
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 960 ? 2 : 1;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: rows.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: AppUIv1.space3,
                      mainAxisSpacing: AppUIv1.space3,
                      mainAxisExtent: 132,
                    ),
                    itemBuilder: (context, index) {
                      final r = rows[index];
                      final color = _statusColor(r.status);
                      return SwPanel(
                        accent: color,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(_statusIcon(r.status), color: color),
                            const SizedBox(width: AppUIv1.space3),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: AppUIv1.space1),
                                  Expanded(
                                    child: Text(
                                      r.details == null ||
                                              r.details!.trim().isEmpty
                                          ? r.message
                                          : '${r.message}\n${r.details}',
                                      overflow: TextOverflow.fade,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            if (_lastRunAt != null) ...[
              const SizedBox(height: AppUIv1.space3),
              Text(
                'Last run: ${_lastRunAt!.toLocal()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_runError != null) ...[
              const SizedBox(height: AppUIv1.space3),
              Text(
                _runError!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppUIv1.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

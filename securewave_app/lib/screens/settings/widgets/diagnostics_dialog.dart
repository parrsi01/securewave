import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/vpn_status.dart';
import '../../../core/services/auth_session.dart';
import '../../../core/state/app_state.dart';
import '../../../ui/design/app_colors.dart';
import '../../../ui/design/app_spacing.dart';

class DiagnosticsDialog extends ConsumerStatefulWidget {
  const DiagnosticsDialog({super.key});

  @override
  ConsumerState<DiagnosticsDialog> createState() => _DiagnosticsDialogState();
}

class _DiagnosticsDialogState extends ConsumerState<DiagnosticsDialog> {
  bool _isRunning = true;
  final List<_DiagnosticResult> _results = [];

  @override
  void initState() {
    super.initState();
    _runChecks();
  }

  Future<void> _runChecks() async {
    final appConfig = ref.read(appConfigProvider);
    final authSession = ref.read(authSessionProvider);
    final vpnService = ref.read(vpnServiceProvider);

    // Check 1: Backend reachability
    final backendUrl = appConfig.apiBaseUrl;
    final backendReachable = backendUrl.isNotEmpty;
    _addResult(
      label: 'Backend endpoint configured',
      passed: backendReachable,
      detail: backendReachable ? backendUrl : 'No API base URL configured',
    );

    // Small delay so the UI feels responsive
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    // Check 2: Auth status
    final isAuthed = authSession.isAuthenticated;
    _addResult(
      label: 'Authentication status',
      passed: isAuthed,
      detail: isAuthed ? 'Signed in' : 'Not signed in',
    );

    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    // Check 3: VPN service native availability
    final nativeAvailable = vpnService.isNativeAvailable;
    _addResult(
      label: 'Native VPN bridge',
      passed: nativeAvailable,
      detail: nativeAvailable ? 'Available' : 'Unavailable',
    );

    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    // Check 4: VPN tunnel status
    final vpnStatus = vpnService.getStatus();
    final tunnelOk = vpnStatus == VpnStatus.connected;
    _addResult(
      label: 'VPN tunnel status',
      passed: tunnelOk,
      detail: vpnStatus.name,
    );

    setState(() => _isRunning = false);
  }

  void _addResult({
    required String label,
    required bool passed,
    required String detail,
  }) {
    if (!mounted) return;
    setState(() {
      _results.add(_DiagnosticResult(
        label: label,
        passed: passed,
        detail: detail,
      ));
    });
  }

  String _buildClipboardText() {
    final buffer = StringBuffer('SecureWave Diagnostics Report\n');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}\n');
    for (final result in _results) {
      final status = result.passed ? 'PASS' : 'FAIL';
      buffer.writeln('[$status] ${result.label}: ${result.detail}');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Diagnostics'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isRunning && _results.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.space6),
                child: CircularProgressIndicator(),
              ),
            ..._results.map((result) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.space1),
                  child: Row(
                    children: [
                      Icon(
                        result.passed
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        size: 20,
                        color: result.passed ? AppColors.success : AppColors.error,
                      ),
                      const SizedBox(width: AppSpacing.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              result.label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              result.detail,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
            if (_isRunning && _results.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.space3),
                child: SizedBox(
                  height: 2,
                  child: LinearProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (!_isRunning)
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy to Clipboard'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _buildClipboardText()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Diagnostics copied to clipboard.')),
              );
            },
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _DiagnosticResult {
  const _DiagnosticResult({
    required this.label,
    required this.passed,
    required this.detail,
  });

  final String label;
  final bool passed;
  final String detail;
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/diagnostic_service.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_ui_v1.dart';
import '../../ui/components/depth_panel.dart';

class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  bool _running = false;
  DiagnosticReport? _report;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runDiagnostics());
    });
  }

  Future<void> _runDiagnostics() async {
    setState(() => _running = true);
    final report =
        await ref.read(vpnStateProvider.notifier).triggerDiagnostic();
    if (mounted) {
      setState(() {
        _report = report;
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final checks = _report?.checks ?? const <DiagnosticCheckResult>[];

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppUIv1.space5),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Diagnostics',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: AppUIv1.space2),
                    Text(
                      'Runtime validation of backend, auth, profile, tunnel, routing, and traffic.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (_report != null) ...[
                      const SizedBox(height: AppUIv1.space2),
                      Text(
                        _report!.summary,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _running ? null : _runDiagnostics,
                icon: const Icon(Icons.refresh),
                label: Text(_running ? 'RETRYING' : 'Run checks'),
              ),
            ],
          ),
          const SizedBox(height: AppUIv1.space4),
          for (final check in checks)
            Padding(
              padding: const EdgeInsets.only(bottom: AppUIv1.space3),
              child: DepthPanel(
                depth: check.passed ? PanelDepth.raised : PanelDepth.floating,
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(
                    check.passed ? Icons.check_circle : Icons.error,
                    color: check.passed ? AppUIv1.success : AppUIv1.danger,
                  ),
                  title: Text(check.label),
                  subtitle: Text(check.detail),
                  trailing: Text(
                    check.passed ? 'OK' : 'FAILED',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              check.passed ? AppUIv1.success : AppUIv1.danger,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
            ),
          if (checks.isEmpty)
            DepthPanel(
              depth: PanelDepth.base,
              padding: const EdgeInsets.all(AppUIv1.space4),
              child: Text(
                _running
                    ? 'Running diagnostics...'
                    : 'No diagnostics have been run yet.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          if (_report != null && _report!.recommendations.isNotEmpty) ...[
            const SizedBox(height: AppUIv1.space4),
            Text('Recommendations',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppUIv1.space3),
            for (final rec in _report!.recommendations)
              Padding(
                padding: const EdgeInsets.only(bottom: AppUIv1.space2),
                child: DepthPanel(
                  depth: PanelDepth.base,
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.lightbulb_outline),
                    title: Text(rec),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

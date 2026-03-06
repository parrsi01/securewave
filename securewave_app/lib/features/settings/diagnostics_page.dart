import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/diagnostics.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_ui_v1.dart';

class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runDiagnostics());
    });
  }

  Future<void> _runDiagnostics() async {
    setState(() => _running = true);
    await ref.read(vpnStateProvider.notifier).refreshDiagnostics();
    if (mounted) {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final checks = ref.watch(
        vpnStateProvider.select((state) => state.checks.values.toList()));

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
              child: Card(
                child: ListTile(
                  leading: Icon(
                    _iconFor(check.status),
                    color: _colorFor(check.status),
                  ),
                  title: Text(check.label),
                  subtitle: Text(check.message),
                  trailing: Text(
                    _labelFor(check.status),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _colorFor(check.status),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
            ),
          if (checks.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppUIv1.space4),
                child: Text(
                  'No diagnostics have been run yet.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconFor(DiagnosticStatus status) {
    switch (status) {
      case DiagnosticStatus.ok:
        return Icons.check_circle;
      case DiagnosticStatus.failed:
        return Icons.error;
      case DiagnosticStatus.retrying:
        return Icons.sync;
    }
  }

  Color _colorFor(DiagnosticStatus status) {
    switch (status) {
      case DiagnosticStatus.ok:
        return AppUIv1.success;
      case DiagnosticStatus.failed:
        return AppUIv1.danger;
      case DiagnosticStatus.retrying:
        return AppUIv1.accentSun;
    }
  }

  String _labelFor(DiagnosticStatus status) {
    switch (status) {
      case DiagnosticStatus.ok:
        return 'OK';
      case DiagnosticStatus.failed:
        return 'FAILED';
      case DiagnosticStatus.retrying:
        return 'RETRYING';
    }
  }
}

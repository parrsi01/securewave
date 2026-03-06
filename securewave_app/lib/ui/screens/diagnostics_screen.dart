import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../debug/automation_keys.dart';
import '../../debug/runtime_diagnostics.dart';
import '../theme/securewave_palette.dart';
import '../layout/page_frame.dart';
import '../widgets/glass_panel.dart';

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(runtimeDiagnosticsProvider);
    return PageFrame(
      eyebrow: 'Diagnostics',
      title: 'Runtime validation',
      subtitle:
          'Live backend, auth, catalog, profile, tunnel, and traffic checks rendered in one operational view.',
      trailing: IconButton(
        tooltip: 'Refresh diagnostics',
        onPressed: () => ref.invalidate(runtimeDiagnosticsProvider),
        icon: const Icon(Icons.refresh_rounded),
      ),
      child: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => GlassPanel(
          child: Text('Diagnostics failed to start: $error'),
        ),
        data: (value) {
          return Column(
            children: <Widget>[
              GlassPanel(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    _SummaryTile(
                        label: 'Connection',
                        value: value.connectionStatus.name),
                    _SummaryTile(
                        label: 'Interface', value: value.interfaceSource),
                    _SummaryTile(
                        label: 'RX bytes', value: value.rxBytes.toString()),
                    _SummaryTile(
                        label: 'TX bytes', value: value.txBytes.toString()),
                  ],
                ),
              ).animate().fadeIn(duration: 260.ms).slideY(begin: 0.05),
              if (value.tunnelActiveButNoTraffic) ...<Widget>[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: SecureWavePalette.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: SecureWavePalette.warning.withValues(alpha: 0.22),
                    ),
                  ),
                  child: const Text(
                    'Tunnel is active but no return traffic was observed. Inspect routing, interface counters, and DNS behavior.',
                  ),
                ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05),
              ],
              const SizedBox(height: 16),
              ...value.checks.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _DiagnosticCard(
                        index: entry.key,
                        check: entry.value,
                      )
                          .animate()
                          .fadeIn(duration: 260.ms, delay: (entry.key * 40).ms)
                          .slideY(begin: 0.04),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.48),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _DiagnosticCard extends StatelessWidget {
  const _DiagnosticCard({
    required this.index,
    required this.check,
  });

  final int index;
  final RuntimeDiagnosticCheck check;

  @override
  Widget build(BuildContext context) {
    final color =
        check.passed ? SecureWavePalette.success : SecureWavePalette.danger;
    return GlassPanel(
      key: ValueKey<String>(
        AutomationKeys.diagnosticsResult(index, check.statusKey),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            check.passed ? Icons.check_circle : Icons.error_outline_rounded,
            color: color,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  check.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  check.detail,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

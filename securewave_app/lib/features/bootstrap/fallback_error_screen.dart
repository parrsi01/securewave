import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import '../../ui/app_ui_v1.dart';
import '../../ui/securewave_ui.dart';

class FallbackErrorScreen extends StatelessWidget {
  const FallbackErrorScreen({
    super.key,
    required this.message,
    this.error,
    this.stackTrace,
  });

  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  @override
  Widget build(BuildContext context) {
    final details = _buildDetails();
    return Scaffold(
      body: SwPage(
        maxWidth: AppUIv1.narrowContentMaxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppUIv1.space6),
            const SwStatusPill(
              label: 'Startup alert',
              color: AppUIv1.danger,
              icon: Icons.error_outline_rounded,
            ),
            const SizedBox(height: AppUIv1.space4),
            Text(
              'SecureWave could not start',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppUIv1.space2),
            Text(
              'Copy the diagnostics below and share with support.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppUIv1.space4),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: details));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Diagnostics copied')),
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy diagnostics'),
            ),
            const SizedBox(height: AppUIv1.space4),
            Expanded(
              child: SwPanel(
                accent: AppUIv1.danger,
                child: SingleChildScrollView(
                  child: SelectableText(
                    details,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildDetails() {
    final logText =
        AppLogger.logStream.value.map((e) => e.toString()).join('\n');
    return [
      'SecureWave Diagnostics',
      'Message: $message',
      if (error != null) 'Error: $error',
      if (stackTrace != null) 'Stack:\n$stackTrace',
      'Logs:',
      logText,
    ].join('\n');
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';

class FallbackErrorScreen extends StatelessWidget {
  const FallbackErrorScreen({super.key, required this.message, this.error, this.stackTrace});

  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  @override
  Widget build(BuildContext context) {
    final details = _buildDetails();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Something went wrong', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: AppSpacing.space2),
              Text(
                'Copy the diagnostics below and share with support.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.space4),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: details));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Diagnostics copied')),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy diagnostics'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space4),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.space3),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(details, style: Theme.of(context).textTheme.bodySmall),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildDetails() {
    final logText = AppLogger.logStream.value.map((e) => e.toString()).join('\n');
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import '../../ui/app_ui_v1.dart';

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
      body: SecurePageBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final padding = AppUIv1.pagePaddingFor(constraints.maxWidth);

              return Padding(
                padding: padding,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppUIv1.contentWideMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SecureSurface(
                          variant: SecureSurfaceVariant.danger,
                          padding: const EdgeInsets.all(AppUIv1.space5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: AppUIv1.danger,
                                size: 30,
                              ),
                              const SizedBox(width: AppUIv1.space3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Something went wrong',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium,
                                    ),
                                    const SizedBox(height: AppUIv1.space1),
                                    Text(
                                      'Copy the diagnostics below and share with support.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                    const SizedBox(height: AppUIv1.space3),
                                    FilledButton.icon(
                                      onPressed: () async {
                                        await Clipboard.setData(
                                          ClipboardData(text: details),
                                        );
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text('Diagnostics copied'),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.copy_rounded),
                                      label: const Text('Copy diagnostics'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppUIv1.space4),
                        Expanded(
                          child: SecureSurface(
                            variant: SecureSurfaceVariant.glass,
                            padding: const EdgeInsets.all(AppUIv1.space4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Diagnostic payload',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: AppUIv1.space3),
                                Expanded(
                                  child: SecureSurface(
                                    variant: SecureSurfaceVariant.base,
                                    padding: const EdgeInsets.all(
                                      AppUIv1.space3,
                                    ),
                                    child: SizedBox.expand(
                                      child: SingleChildScrollView(
                                        child: SelectableText(
                                          details,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
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

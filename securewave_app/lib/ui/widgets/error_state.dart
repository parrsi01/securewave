import 'package:flutter/material.dart';
import '../design/app_colors.dart';
import '../design/app_spacing.dart';

/// Error state component.
///
/// Displays when an error occurs with retry and dismiss actions.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.title,
    this.message,
    this.onRetry,
    this.onDismiss,
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error.withValues(alpha: 0.7),
            ),
            const SizedBox(height: AppSpacing.space4),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.error,
                  ),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.space2),
              Text(
                message!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.inkMuted,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: AppSpacing.space5),
            Wrap(
              spacing: AppSpacing.space3,
              runSpacing: AppSpacing.space3,
              alignment: WrapAlignment.center,
              children: [
                if (onRetry != null)
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                if (onDismiss != null)
                  OutlinedButton(
                    onPressed: onDismiss,
                    child: const Text('Dismiss'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

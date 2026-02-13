import 'package:flutter/material.dart';
import '../design/app_colors.dart';
import '../design/app_spacing.dart';

/// Empty state component.
///
/// Displays when a list or content area has no data.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final EmptyStateAction? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: AppColors.inkSoft.withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppSpacing.space4),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.inkMuted,
                  ),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.space2),
              Text(
                message!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.inkSoft,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.space5),
              FilledButton.icon(
                onPressed: action!.onTap,
                icon: Icon(action!.icon),
                label: Text(action!.label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Empty state action button configuration.
class EmptyStateAction {
  const EmptyStateAction({
    required this.label,
    required this.onTap,
    this.icon = Icons.refresh,
  });

  final String label;
  final VoidCallback onTap;
  final IconData icon;
}

import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_spacing.dart';

/// Describes an action button shown below the empty state.
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

/// Generic empty state placeholder — icon, title, optional message, optional
/// action button.
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
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.inkSoft),
            const SizedBox(height: AppSpacing.space4),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
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
              OutlinedButton.icon(
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

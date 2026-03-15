import 'package:flutter/material.dart';

import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';

/// Feedback category options for the feedback sheet.
enum FeedbackCategory {
  bugReport('Bug Report'),
  featureRequest('Feature Request'),
  generalFeedback('General Feedback');

  const FeedbackCategory(this.label);
  final String label;
}

/// A modal bottom sheet for submitting user feedback or bug reports.
///
/// Shows a category selector (SegmentedButton), a multiline text field,
/// and a submit button.
///
/// Usage:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,
///   builder: (_) => FeedbackSheet(
///     onSubmit: (category, description) { /* handle */ },
///   ),
/// );
/// ```
class FeedbackSheet extends StatefulWidget {
  const FeedbackSheet({super.key, required this.onSubmit});

  /// Called when the user taps Submit.
  /// Provides the selected [FeedbackCategory] and the description text.
  final void Function(FeedbackCategory category, String description) onSubmit;

  @override
  State<FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<FeedbackSheet> {
  FeedbackCategory _category = FeedbackCategory.bugReport;
  final TextEditingController _descriptionController = TextEditingController();

  bool get _canSubmit => _descriptionController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    if (!_canSubmit) return;
    widget.onSubmit(_category, _descriptionController.text.trim());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Account for keyboard height so the sheet scrolls properly.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space5,
              vertical: AppSpacing.space5,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Drag Handle ─────────────────────────────────────────
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusFull,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.space5),

                // ── Title ───────────────────────────────────────────────
                const Text(
                  'Send Feedback',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: AppSpacing.space5),

                // ── Category Selector ───────────────────────────────────
                SegmentedButton<FeedbackCategory>(
                  segments: FeedbackCategory.values
                      .map(
                        (cat) => ButtonSegment<FeedbackCategory>(
                          value: cat,
                          label: Text(
                            cat.label,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                  selected: {_category},
                  onSelectionChanged: (selection) {
                    setState(() => _category = selection.first);
                  },
                  style: ButtonStyle(
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusS,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.space5),

                // ── Description Field ───────────────────────────────────
                TextField(
                  controller: _descriptionController,
                  maxLines: null,
                  minLines: 4,
                  textInputAction: TextInputAction.newline,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Describe your feedback...',
                    hintStyle: const TextStyle(color: AppColors.inkSoft),
                    filled: true,
                    fillColor: AppColors.surfaceMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusM),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.all(AppSpacing.space4),
                  ),
                ),
                const SizedBox(height: AppSpacing.space5),

                // ── Submit Button ───────────────────────────────────────
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _canSubmit ? _handleSubmit : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.border,
                      disabledForegroundColor: AppColors.inkSoft,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusM,
                        ),
                      ),
                    ),
                    child: const Text(
                      'Submit',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

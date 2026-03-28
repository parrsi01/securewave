import 'package:flutter/material.dart';

import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/theme/app_colors.dart' as htb;
import '../../ui/theme/app_theme.dart' as legacy;
import '../../ui/theme/app_typography.dart';
import '../../ui/widgets/vpn_ui_bindings.dart';

export '../../ui/design/app_colors.dart';
export '../../ui/design/app_spacing.dart';
export '../../ui/theme/app_colors.dart' show HtbColors;
export '../../ui/theme/app_typography.dart';

/// Central Flutter theme entry point for SecureWave.
///
/// This wraps the concrete Material theme implementation in `ui/theme` and
/// keeps shared visual mappings in one place so widgets do not carry their own
/// ad hoc palettes or gradients.
class AppTheme {
  AppTheme._();

  static ThemeData dark() => legacy.HtbTheme.dark();

  static TextTheme textTheme() => AppTypography.textTheme();

  static const Color ringForegroundColor = Colors.white;
  static const Color ringOutlineColor = Color(0x26FFFFFF);
  static const Color ringSpinnerColor = Color(0x99FFFFFF);

  static const LinearGradient _errorGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.error, AppColors.errorDark],
  );

  static const List<LinearGradient> onboardingGradients = <LinearGradient>[
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.primaryBright, AppColors.primaryDeep],
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.primary, AppColors.primaryDark],
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.primaryBright, AppColors.primary],
    ),
  ];

  static LinearGradient onboardingGradient(int index) {
    final safeIndex = index.clamp(0, onboardingGradients.length - 1);
    return onboardingGradients[safeIndex];
  }

  static Gradient connectionGradient(ConnectionVisualState state) =>
      switch (state) {
        ConnectionVisualState.connected => AppColors.connectedGradient,
        ConnectionVisualState.error => _errorGradient,
        _ => AppColors.brandGradient,
      };

  static Color connectionColor(ConnectionVisualState state) => switch (state) {
        ConnectionVisualState.connected => AppColors.primaryBright,
        ConnectionVisualState.connecting => AppColors.warning,
        ConnectionVisualState.reconnecting => AppColors.warning,
        ConnectionVisualState.disconnecting => AppColors.darkInkSoft,
        ConnectionVisualState.error => AppColors.error,
        ConnectionVisualState.disconnected => AppColors.darkInkSoft,
      };

  static BoxDecoration authErrorDecoration({
    double radius = AppSpacing.radiusL,
  }) {
    return BoxDecoration(
      color: htb.HtbColors.statusDisconnected.withValues(alpha: 0.08),
      border: Border.all(
        color: htb.HtbColors.statusDisconnected.withValues(alpha: 0.22),
      ),
      borderRadius: BorderRadius.circular(radius),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class AppUIv1 {
  AppUIv1._();

  static const Color background = AppColors.background;
  static const Color backgroundStrong = AppColors.backgroundWarm;
  static const Color surface = AppColors.surface;
  static const Color surfaceMuted = AppColors.surfaceMuted;
  static const Color surfaceElevated = AppColors.surfaceElevated;
  static const Color panelSunken = AppColors.surfaceSunken;
  static const Color panelBase = AppColors.surfaceBase;
  static const Color panelRaised = AppColors.surfaceRaised;
  static const Color panelFloating = AppColors.surfaceFloating;

  static const Color accent = AppColors.primary;
  static const Color accentStrong = AppColors.primaryDark;
  static const Color accentSoft = AppColors.primaryDeep;
  static const Color accentSun = AppColors.warning;

  static const Color success = AppColors.success;
  static const Color warning = AppColors.warning;
  static const Color danger = AppColors.error;

  static const Color ink = AppColors.ink;
  static const Color inkMuted = AppColors.inkMuted;
  static const Color inkSoft = AppColors.inkSoft;
  static const Color border = AppColors.border;
  static const Color borderSubtle = AppColors.borderSubtle;
  static const Color borderStrong = AppColors.borderStrong;

  static const double space1 = AppSpacing.space1;
  static const double space2 = AppSpacing.space2;
  static const double space3 = AppSpacing.space3;
  static const double space4 = AppSpacing.space4;
  static const double space5 = AppSpacing.space5;
  static const double space6 = AppSpacing.space6;
  static const double space7 = AppSpacing.space7;

  static ThemeData theme() => AppTheme.dark();

  static String formatBytes(double bytesPerSecond) {
    if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    if (bytesPerSecond >= 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${bytesPerSecond.toStringAsFixed(0)} B/s';
  }

  static String formatDataAmount(int bytes) {
    final kb = bytes / 1024;
    final mb = kb / 1024;
    final gb = mb / 1024;
    if (gb >= 1) {
      return '${gb.toStringAsFixed(2)} GB';
    }
    if (mb >= 1) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    if (kb >= 1) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  static String formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}

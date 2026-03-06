import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'theme/securewave_theme.dart';
import 'theme/spacing.dart';

class AppUIv1 {
  const AppUIv1._();

  static const Color background = SecureWaveTokens.background;
  static const Color backgroundStrong = SecureWaveTokens.backgroundStrong;
  static const Color surface = SecureWaveTokens.surface;
  static const Color surfaceMuted = SecureWaveTokens.surfaceMuted;
  static const Color accent = SecureWaveTokens.accent;
  static const Color accentStrong = SecureWaveTokens.accentStrong;
  static const Color accentSoft = SecureWaveTokens.accentSoft;
  static const Color accentSun = SecureWaveTokens.accentSun;
  static const Color success = SecureWaveTokens.success;
  static const Color warning = SecureWaveTokens.warning;
  static const Color danger = SecureWaveTokens.danger;
  static const Color ink = SecureWaveTokens.ink;
  static const Color inkMuted = SecureWaveTokens.inkMuted;
  static const Color inkSoft = SecureWaveTokens.inkSoft;
  static const Color border = SecureWaveTokens.border;

  static const double space1 = SecureWaveSpacing.xxs;
  static const double space2 = SecureWaveSpacing.xs;
  static const double space3 = SecureWaveSpacing.sm;
  static const double space4 = SecureWaveSpacing.md;
  static const double space5 = SecureWaveSpacing.lg;
  static const double space6 = SecureWaveSpacing.xl;
  static const double space7 = SecureWaveSpacing.xxl;

  static ThemeData theme() => SecureWaveTheme.dark();

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

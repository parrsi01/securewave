import 'dart:io' show Platform;
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// SecureWave typography system using Manrope font.
///
/// On Linux, falls back to system fonts to avoid Skia rendering issues.
class AppTypography {
  AppTypography._();

  /// Creates a Material 3 TextTheme using Manrope font.
  ///
  /// Falls back to system fonts on Linux to avoid Skia crashes.
  static TextTheme textTheme(TextTheme base, {bool isDark = false}) {
    // Manrope on all platforms except Linux (Skia rendering workaround)
    final TextTheme theme = (!kIsWeb && Platform.isLinux)
        ? base
        : GoogleFonts.manropeTextTheme(base);

    final ink = isDark ? AppColors.darkInk : AppColors.ink;
    final inkMuted = isDark ? AppColors.darkInkMuted : AppColors.inkMuted;
    final inkSoft = isDark ? AppColors.darkInkSoft : AppColors.inkSoft;

    return theme.copyWith(
      // ── Display ───────────────────────────────────────────────────────
      displayLarge: theme.displayLarge?.copyWith(
          fontWeight: FontWeight.w800, color: ink, letterSpacing: -1.5),
      displayMedium: theme.displayMedium?.copyWith(
          fontWeight: FontWeight.w800, color: ink, letterSpacing: -1.0),
      displaySmall: theme.displaySmall?.copyWith(
          fontWeight: FontWeight.w700, color: ink, letterSpacing: -0.5),

      // ── Headline ──────────────────────────────────────────────────────
      headlineLarge: theme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700, color: ink, letterSpacing: -0.5),
      headlineMedium: theme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700, color: ink, letterSpacing: -0.3),
      headlineSmall: theme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600, color: ink, letterSpacing: -0.2),

      // ── Title ─────────────────────────────────────────────────────────
      titleLarge: theme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700, color: ink, letterSpacing: -0.3),
      titleMedium: theme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600, color: ink, letterSpacing: -0.1),
      titleSmall:
          theme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: ink),

      // ── Body ──────────────────────────────────────────────────────────
      bodyLarge: theme.bodyLarge?.copyWith(color: ink, height: 1.55),
      bodyMedium: theme.bodyMedium?.copyWith(color: inkMuted, height: 1.5),
      bodySmall: theme.bodySmall?.copyWith(color: inkSoft, height: 1.45),

      // ── Label ─────────────────────────────────────────────────────────
      labelLarge: theme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700, color: ink, letterSpacing: 0.1),
      labelMedium: theme.labelMedium
          ?.copyWith(fontWeight: FontWeight.w600, color: inkMuted),
      labelSmall: theme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600, color: inkSoft, letterSpacing: 0.3),
    );
  }

  /// Check if running on Apple platform (for Cupertino styles)
  static bool get isApplePlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }
}

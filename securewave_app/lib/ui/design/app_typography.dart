import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
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
  static TextTheme textTheme(TextTheme base) {
    // Use Google Fonts on iOS/Android/Windows/macOS/Web
    // Use system fonts on Linux to avoid Skia rendering crashes
    final TextTheme theme = (!kIsWeb && Platform.isLinux)
        ? base
        : GoogleFonts.manropeTextTheme(base);

    // Apply custom font weights and colors
    return theme.copyWith(
      // ── Display Styles ────────────────────────────────────────────────
      displayLarge: theme.displayLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      displayMedium: theme.displayMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      displaySmall: theme.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),

      // ── Headline Styles ───────────────────────────────────────────────
      headlineLarge: theme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      headlineMedium: theme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      headlineSmall: theme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),

      // ── Title Styles ──────────────────────────────────────────────────
      titleLarge: theme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      titleMedium: theme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      titleSmall: theme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),

      // ── Body Styles ───────────────────────────────────────────────────
      bodyLarge: theme.bodyLarge?.copyWith(
        color: AppColors.ink,
      ),
      bodyMedium: theme.bodyMedium?.copyWith(
        color: AppColors.inkMuted,
      ),
      bodySmall: theme.bodySmall?.copyWith(
        color: AppColors.inkSoft,
      ),

      // ── Label Styles ──────────────────────────────────────────────────
      labelLarge: theme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      labelMedium: theme.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.inkMuted,
      ),
      labelSmall: theme.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.inkSoft,
      ),
    );
  }

  /// Check if running on Apple platform (for Cupertino styles)
  static bool get isApplePlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }
}

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// SecureWave elevation & shadow tokens — v2.
///
/// Material 3 uses tonal elevation (color tinting) rather than drop shadows.
/// SecureWave adds a supplementary box-shadow layer for premium depth feel.
/// Use these in Container/Card decorations to add layered depth.
class AppElevation {
  AppElevation._();

  // ── Light Mode Shadows ───────────────────────────────────────────────────

  /// No shadow — flush to surface
  static const List<BoxShadow> none = [];

  /// Ultra-subtle outline shadow (replaces visible borders)
  static List<BoxShadow> get hairline => [
        BoxShadow(
          color: AppColors.ink.withValues(alpha: 0.04),
          blurRadius: 1,
          offset: const Offset(0, 1),
        ),
      ];

  /// Low elevation — list tiles, chips, pills
  static List<BoxShadow> get low => [
        BoxShadow(
          color: AppColors.ink.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: AppColors.ink.withValues(alpha: 0.02),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];

  /// Medium elevation — cards, panels
  static List<BoxShadow> get medium => [
        BoxShadow(
          color: AppColors.ink.withValues(alpha: 0.07),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: AppColors.ink.withValues(alpha: 0.03),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];

  /// High elevation — modals, bottom sheets, dropdowns
  static List<BoxShadow> get high => [
        BoxShadow(
          color: AppColors.ink.withValues(alpha: 0.10),
          blurRadius: 40,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: AppColors.ink.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ];

  // ── Teal Glow Shadows (brand accent) ─────────────────────────────────────

  /// Teal glow — connection ring (disconnected idle)
  static List<BoxShadow> get tealGlowSm => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.15),
          blurRadius: 20,
          spreadRadius: 2,
        ),
      ];

  /// Teal glow — connection ring (connected pulse)
  static List<BoxShadow> tealGlowPulse(double intensity) => [
        BoxShadow(
          color: AppColors.success.withValues(alpha: 0.12 + intensity * 0.18),
          blurRadius: 32 + intensity * 16,
          spreadRadius: 4 + intensity * 4,
        ),
      ];

  // ── Dark Mode Shadows ─────────────────────────────────────────────────────

  /// Low elevation — dark mode
  static List<BoxShadow> get darkLow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.20),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  /// Medium elevation — dark mode
  static List<BoxShadow> get darkMedium => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.30),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.15),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];

  // ── Glassmorphism Shadow ─────────────────────────────────────────────────

  /// Inner glow for glass cards
  static List<BoxShadow> get glass => [
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.08),
          blurRadius: 1,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: AppColors.ink.withValues(alpha: 0.06),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  // ── Helper: Adaptive ─────────────────────────────────────────────────────

  /// Returns light or dark shadow based on [brightness].
  static List<BoxShadow> adaptive(Brightness brightness,
      {required List<BoxShadow> light, required List<BoxShadow> dark}) {
    return brightness == Brightness.dark ? dark : light;
  }
}

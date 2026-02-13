import 'package:flutter/material.dart';

/// SecureWave color palette.
///
/// Extracted from AppUIv1 to preserve exact brand identity.
/// Primary: Teal accent (#1B6B68)
/// Secondary: Yellow/gold (#F6C14D)
class AppColors {
  AppColors._();

  // ── Primary (Teal) ──────────────────────────────────────────────────────

  /// Primary brand color - Teal accent
  static const Color primary = Color(0xFF1B6B68);

  /// Darker teal for hover/pressed states
  static const Color primaryDark = Color(0xFF0F4F4C);

  /// Light teal for backgrounds/indicators
  static const Color primaryLight = Color(0xFFD5EFEC);

  // ── Secondary (Yellow/Gold) ─────────────────────────────────────────────

  /// Secondary accent color - Yellow/gold
  static const Color secondary = Color(0xFFF6C14D);

  // ── Semantic Colors ─────────────────────────────────────────────────────

  /// Success state (green)
  static const Color success = Color(0xFF1F8F5C);

  /// Warning state (orange)
  static const Color warning = Color(0xFFC26B1F);

  /// Error/danger state (red)
  static const Color error = Color(0xFFB3261E);

  // ── Surfaces & Backgrounds ──────────────────────────────────────────────

  /// Primary background color (white)
  static const Color background = Color(0xFFFFFFFF);

  /// Stronger background (light gray)
  static const Color backgroundStrong = Color(0xFFF5F5F5);

  /// Surface color (white)
  static const Color surface = Color(0xFFFFFFFF);

  /// Muted surface color (light gray)
  static const Color surfaceMuted = Color(0xFFF5F5F5);

  // ── Text & Ink Colors ───────────────────────────────────────────────────

  /// Primary text color (dark blue-black)
  static const Color ink = Color(0xFF0B1F2A);

  /// Secondary text color (medium gray)
  static const Color inkMuted = Color(0xFF4A5B66);

  /// Tertiary text color (light gray)
  static const Color inkSoft = Color(0xFF72838F);

  // ── Borders & Dividers ──────────────────────────────────────────────────

  /// Border and divider color (light gray)
  static const Color border = Color(0xFFE0E0E0);

  // ── Material 3 ColorScheme Builder ──────────────────────────────────────

  /// Creates a Material 3 ColorScheme using SecureWave brand colors.
  static ColorScheme colorScheme({Brightness brightness = Brightness.light}) {
    return ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: Colors.white,
      secondary: secondary,
      onSecondary: ink,
      error: error,
      onError: Colors.white,
      surface: surface,
      onSurface: ink,
    );
  }
}

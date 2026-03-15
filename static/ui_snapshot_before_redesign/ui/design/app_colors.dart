import 'package:flutter/material.dart';

/// SecureWave color system — v2 redesign.
///
/// Teal brand (#1B6B68) preserved exactly. New: full dark palette,
/// teal-tinted neutrals, glassmorphism tokens, and semantic depth layers.
class AppColors {
  AppColors._();

  // ── Brand Primary (Teal) ────────────────────────────────────────────────

  static const Color primary = Color(0xFF1B6B68);
  static const Color primaryDark = Color(0xFF0F4F4C);
  static const Color primaryDeep = Color(0xFF093837);

  /// Lighter interactive teal (better on dark backgrounds)
  static const Color primaryBright = Color(0xFF26A09B);

  /// Very light teal for highlights & light-mode chip fills
  static const Color primaryLight = Color(0xFFD5EFEC);

  /// Translucent teal overlay
  static const Color primaryGhost = Color(0x141B6B68);

  // ── Secondary (Gold) ───────────────────────────────────────────────────

  static const Color secondary = Color(0xFFF6C14D);
  static const Color secondaryDark = Color(0xFFC28A10);

  // ── Semantic ───────────────────────────────────────────────────────────

  static const Color success = Color(0xFF1F8F5C);
  static const Color warning = Color(0xFFC26B1F);
  static const Color error = Color(0xFFB3261E);

  static const Color successLight = Color(0xFFD4F0E4);
  static const Color warningLight = Color(0xFFF9E5D0);
  static const Color errorLight = Color(0xFFF5D6D4);

  // ── Light Mode Surfaces ────────────────────────────────────────────────

  static const Color background = Color(0xFFFAFBFC);
  static const Color backgroundWarm = Color(0xFFF4F6F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF2F5F7);
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  // ── Light Mode Text ────────────────────────────────────────────────────

  static const Color ink = Color(0xFF0B1F2A);
  static const Color inkMuted = Color(0xFF4A5B66);
  static const Color inkSoft = Color(0xFF8A9BA6);

  // ── Light Mode Borders ─────────────────────────────────────────────────

  static const Color border = Color(0xFFE2E8ED);
  static const Color borderFocus = Color(0xFF1B6B68);

  // ── Dark Mode Surfaces (navy-teal family) ─────────────────────────────

  static const Color darkBackground = Color(0xFF051E1C);   // deep teal-navy
  static const Color darkBackgroundWarm = Color(0xFF072320); // slightly warmer
  static const Color darkSurface = Color(0xFF0C3230);        // card surface
  static const Color darkSurfaceMuted = Color(0xFF0F3D3A);   // muted card
  static const Color darkSurfaceElevated = Color(0xFF144845); // elevated card

  // ── Dark Mode Text ─────────────────────────────────────────────────────

  static const Color darkInk = Color(0xFFF0F9F8);          // near-white
  static const Color darkInkMuted = Color(0xFFB2D4D2);      // muted teal-white
  static const Color darkInkSoft = Color(0xFF6FA8A5);       // soft teal-grey

  // ── Dark Mode Borders ──────────────────────────────────────────────────

  static const Color darkBorder = Color(0xFF1A4E4B);        // teal border
  static const Color darkBorderFocus = Color(0xFF26A09B);   // focus teal

  // ── Glassmorphism Tokens ──────────────────────────────────────────────

  /// Frosted glass fill — light mode
  static Color get glassFillLight =>
      const Color(0xFFFFFFFF).withValues(alpha: 0.72);

  /// Frosted glass fill — dark mode
  static Color get glassFillDark =>
      const Color(0xFF0C3230).withValues(alpha: 0.80);

  /// Glass border — light mode
  static Color get glassBorderLight =>
      const Color(0xFFFFFFFF).withValues(alpha: 0.4);

  /// Glass border — dark mode
  static Color get glassBorderDark =>
      const Color(0xFF26A09B).withValues(alpha: 0.12);

  // ── Gradient Presets ──────────────────────────────────────────────────

  /// Hero radial gradient (light mode) — centered on the connection ring
  static const Gradient heroGradientLight = RadialGradient(
    center: Alignment.topCenter,
    radius: 1.2,
    colors: [Color(0xFFE8F5F4), Color(0xFFFAFBFC)],
    stops: [0.0, 1.0],
  );

  /// Hero radial gradient (dark mode)
  static const Gradient heroGradientDark = RadialGradient(
    center: Alignment.topCenter,
    radius: 1.2,
    colors: [Color(0xFF0D2A3A), Color(0xFF07121C)],
    stops: [0.0, 1.0],
  );

  /// Deep navy gradient — primary CTA (connect button, avatar, badges)
  static const Gradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F4F4C), Color(0xFF07121C)],
  );

  /// Auth screen header gradient (dark login page)
  static const Gradient authHeaderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B6B68), Color(0xFF093837)],
  );

  /// Connected state gradient — deep teal-navy
  static const Gradient connectedGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F4F4C), Color(0xFF07121C)],
  );

  // ── ColorScheme Builders ──────────────────────────────────────────────

  static ColorScheme lightScheme() {
    return ColorScheme.fromSeed(
      seedColor: primaryDeep,
      brightness: Brightness.light,
    ).copyWith(
      primary: primaryDeep,
      onPrimary: Colors.white,
      primaryContainer: primaryLight,
      onPrimaryContainer: primaryDeep,
      secondary: secondary,
      onSecondary: ink,
      secondaryContainer: const Color(0xFFFEF3D8),
      onSecondaryContainer: const Color(0xFF5A3800),
      error: error,
      onError: Colors.white,
      surface: surface,
      onSurface: ink,
      surfaceContainerHighest: surfaceMuted,
      onSurfaceVariant: inkMuted,
      outline: border,
      outlineVariant: const Color(0xFFEDF0F3),
      shadow: const Color(0xFF0B1F2A),
      scrim: const Color(0xFF0B1F2A),
    );
  }

  static ColorScheme darkScheme() {
    return ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: primaryBright,
      onPrimary: darkBackground,
      primaryContainer: darkSurfaceElevated,
      onPrimaryContainer: primaryLight,
      secondary: primaryLight,
      onSecondary: primaryDeep,
      surface: darkSurface,
      onSurface: darkInk,
      surfaceContainerLowest: darkBackground,
      surfaceContainerLow: darkBackgroundWarm,
      surfaceContainer: darkSurface,
      surfaceContainerHigh: darkSurfaceMuted,
      surfaceContainerHighest: darkSurfaceElevated,
      onSurfaceVariant: darkInkMuted,
      outline: darkBorder,
      outlineVariant: const Color(0xFF0F3533),
      error: const Color(0xFFFF6B6B),
      onError: darkBackground,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: darkInk,
      onInverseSurface: darkBackground,
      inversePrimary: primaryDeep,
    );
  }
}

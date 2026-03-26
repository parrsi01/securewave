import 'package:flutter/material.dart';

/// SecureWave color system.
///
/// New global palette:
/// - near-black foundations
/// - softened blue primary accent
/// - muted orchid / iris secondary accents
/// - calmer contrast and glow for long-session readability
class AppColors {
  AppColors._();

  // ── Accent Colors ────────────────────────────────────────────────────────

  static const Color primary = Color(0xFF6E9FDD);
  static const Color primaryDark = Color(0xFF4B72B7);
  static const Color primaryDeep = Color(0xFF16243D);
  static const Color primaryBright = Color(0xFF8EC5FF);
  static const Color primaryLight = Color(0xFFE2EEFF);

  static const Color primaryGhost = Color(0x148EC5FF);
  static const Color primaryWash = Color(0x108EC5FF);

  static const Color secondary = Color(0xFFD887F5);
  static const Color secondaryDark = Color(0xFF8C74E6);
  static const Color secondaryLight = Color(0xFFF0E7FF);
  static const Color secondaryWash = Color(0x108C74E6);

  // ── Semantic / Status ────────────────────────────────────────────────────

  static const Color success = primaryBright;
  static const Color successDark = primaryDark;
  static const Color warning = Color(0xFFFFB454);
  static const Color warningDark = Color(0xFFC27A18);
  static const Color error = Color(0xFFFF6A8B);
  static const Color errorDark = Color(0xFFB83252);

  static const Color successLight = primaryLight;
  static const Color warningLight = Color(0xFFF8E3C9);
  static const Color errorLight = Color(0xFFF5D3DB);

  // ── Light Mode Surfaces ──────────────────────────────────────────────────

  static const Color background = Color(0xFFF8F7FB);
  static const Color backgroundWarm = Color(0xFFF2F0F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF2F1F7);
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  // ── Light Mode Text ──────────────────────────────────────────────────────

  static const Color ink = Color(0xFF13111B);
  static const Color inkMuted = Color(0xFF5F5A74);
  static const Color inkSoft = Color(0xFF8A839D);

  // ── Light Mode Borders ───────────────────────────────────────────────────

  static const Color border = Color(0xFFD9D4E5);
  static const Color borderFocus = primary;

  // ── Dark Mode Surfaces ───────────────────────────────────────────────────

  static const Color darkBackground = Color(0xFF050508);
  static const Color darkBackgroundWarm = Color(0xFF0B0B0F);
  static const Color darkSurface = Color(0xFF111117);
  static const Color darkSurfaceMuted = Color(0xFF15151C);
  static const Color darkSurfaceElevated = Color(0xFF1A1A22);

  // ── Dark Mode Text ───────────────────────────────────────────────────────

  static const Color darkInk = Color(0xFFFAFAFF);
  static const Color darkInkMuted = Color(0xFFB7B5C9);
  static const Color darkInkSoft = Color(0xFF7F7B96);

  // ── Dark Mode Borders ────────────────────────────────────────────────────

  static const Color darkBorder = Color(0xFF2A2737);
  static const Color darkBorderFocus = primaryBright;
  static const Color darkGridLine = Color(0x0D8C74E6);

  // ── Ambient Glows ────────────────────────────────────────────────────────

  static const Color ambientGlowPrimary = Color(0x148EC5FF);
  static const Color ambientGlowSecondary = Color(0x12D887F5);
  static const Color ambientGlowTertiary = Color(0x108C74E6);

  // ── Glass Tokens ─────────────────────────────────────────────────────────

  static Color get glassFillLight =>
      const Color(0xFFFFFFFF).withValues(alpha: 0.74);

  static Color get glassFillDark =>
      const Color(0xFF0B0B0F).withValues(alpha: 0.82);

  static Color get glassBorderLight =>
      const Color(0xFFFFFFFF).withValues(alpha: 0.38);

  static Color get glassBorderDark =>
      const Color(0xFF8C74E6).withValues(alpha: 0.18);

  // ── Gradient Presets ─────────────────────────────────────────────────────

  static const Gradient heroGradientLight = RadialGradient(
    center: Alignment.topCenter,
    radius: 1.2,
    colors: [Color(0xFFF7F6FF), Color(0xFFFFF0FC)],
    stops: [0.0, 1.0],
  );

  static const Gradient heroGradientDark = RadialGradient(
    center: Alignment.topCenter,
    radius: 1.2,
    colors: [Color(0xFF18131F), darkBackground],
    stops: [0.0, 1.0],
  );

  static const Gradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [secondary, secondaryDark, primaryBright],
  );

  static const Gradient authHeaderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [secondaryDark, secondary, primaryBright],
  );

  static const Gradient connectedGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [secondaryDark, primary, primaryBright],
  );

  static const Gradient navyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [darkBackgroundWarm, darkBackground],
  );

  static const Gradient cyanGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [secondaryDark, secondary],
  );

  // ── ColorScheme Builders ────────────────────────────────────────────────

  static ColorScheme lightScheme() {
    return ColorScheme.fromSeed(
      seedColor: primaryBright,
      brightness: Brightness.light,
    ).copyWith(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: primaryLight,
      onPrimaryContainer: primaryDeep,
      secondary: secondary,
      onSecondary: Colors.white,
      secondaryContainer: secondaryLight,
      onSecondaryContainer: const Color(0xFF3A215E),
      error: errorDark,
      onError: Colors.white,
      surface: surface,
      onSurface: ink,
      surfaceContainerHighest: surfaceMuted,
      onSurfaceVariant: inkMuted,
      outline: border,
      outlineVariant: const Color(0xFFE8E3F0),
      shadow: ink,
      scrim: ink,
    );
  }

  static ColorScheme darkScheme() {
    return ColorScheme.fromSeed(
      seedColor: primaryBright,
      brightness: Brightness.dark,
    ).copyWith(
      primary: primaryBright,
      onPrimary: darkBackground,
      primaryContainer: darkSurfaceElevated,
      onPrimaryContainer: primaryLight,
      secondary: secondary,
      onSecondary: darkBackground,
      surface: darkSurface,
      onSurface: darkInk,
      surfaceContainerLowest: darkBackground,
      surfaceContainerLow: darkBackgroundWarm,
      surfaceContainer: darkSurface,
      surfaceContainerHigh: darkSurfaceMuted,
      surfaceContainerHighest: darkSurfaceElevated,
      onSurfaceVariant: darkInkMuted,
      outline: darkBorder,
      outlineVariant: const Color(0xFF211F2B),
      error: error,
      onError: darkBackground,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: darkInk,
      onInverseSurface: darkBackground,
      inversePrimary: secondaryDark,
    );
  }
}

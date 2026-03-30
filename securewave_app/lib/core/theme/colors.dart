import 'package:flutter/material.dart';

/// SecureWave shared dark palette.
///
/// Calm neutral-dark surfaces with a single neon purple accent.
/// Semantic warning/error colors remain available for state feedback.
class AppColors {
  AppColors._();

  // ── Primary (Neon Purple) ─────────────────────────────────────────────────

  static const Color primary = Color(0xFF7A5CFF);
  static const Color primaryDark = Color(0xFF6248D8);
  static const Color primaryDeep = Color(0xFF24183E);
  static const Color primaryBright = Color(0xFFA28FFF);
  // primaryLight removed — was identical to primaryDeep (0xFF24183E). Use primaryDeep.

  static const Color primaryGhost = Color(0x147A5CFF);
  static const Color primaryWash = Color(0x1E7A5CFF);

  // Legacy secondary/tertiary aliases stay inside the same purple family while
  // mapping to the brighter accent used by the modern UI theme.
  static const Color secondary = primaryBright;
  static const Color secondaryDark = primaryDark;
  static const Color secondaryLight = primaryDeep;
  static const Color secondaryWash = primaryWash;

  static const Color tertiary = primaryBright;
  static const Color tertiaryDark = primaryDark;

  // ── Semantic / Status ─────────────────────────────────────────────────────

  static const Color success = primary;
  static const Color successDark = primaryDark;
  static const Color warning = Color(0xFFFFB454);
  static const Color warningDark = Color(0xFFD68910);
  static const Color error = Color(0xFFFF4D6A);
  static const Color errorDark = Color(0xFFCC3355);

  static const Color successLight = primaryDeep;
  static const Color warningLight = Color(0xFF221A0D);
  static const Color errorLight = Color(0xFF220D12);

  // ── Surfaces ──────────────────────────────────────────────────────────────

  static const Color background = Color(0xFF07090F);
  static const Color backgroundWarm = Color(0xFF0C1018);
  static const Color surface = Color(0xFF101620);
  static const Color surfaceMuted = Color(0xFF121824);
  static const Color surfaceElevated = Color(0xFF171F2D);
  static const Color surfaceOverlay = Color(0xFF1E2736);

  // Semantic surface tiers for layered panels.
  static const Color surfaceSunken = backgroundWarm;
  static const Color surfaceBase = surface;
  static const Color surfaceRaised = surfaceMuted;
  static const Color surfaceFloating = surfaceElevated;

  // ── Text ──────────────────────────────────────────────────────────────────

  static const Color ink = Color(0xFFF3F5FB);
  static const Color inkMuted = Color(0xFFC7CDDD);
  static const Color inkSoft = Color(0xFF97A0B3);

  // ── Borders ───────────────────────────────────────────────────────────────

  static const Color border = Color(0xFF2A3140);
  static const Color borderFocus = primary;
  static const Color borderSubtle = Color(0xFF1B202D);
  static const Color borderStrong = Color(0xFF3A4255);
  static const Color borderAccent = Color(0x337A5CFF);

  // ── Ambient Glows ─────────────────────────────────────────────────────────

  static const Color ambientGlowPrimary = Color(0x147A5CFF);
  static const Color ambientGlowSecondary = Color(0x0D7A5CFF);
  static const Color ambientGlowTertiary = Color(0x087A5CFF);

  // ── Glass Tokens ─────────────────────────────────────────────────────────

  static Color get glassFillLight =>
      const Color(0xFF121824).withValues(alpha: 0.92);

  static Color get glassFillDark =>
      const Color(0xFF07090F).withValues(alpha: 0.92);

  static Color get glassBorderLight =>
      const Color(0xFF7A5CFF).withValues(alpha: 0.24);

  static Color get glassBorderDark =>
      const Color(0xFF7A5CFF).withValues(alpha: 0.24);

  // ── Gradient Presets ─────────────────────────────────────────────────────

  static const Gradient heroGradientLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [background, backgroundWarm],
    stops: [0.0, 1.0],
  );

  static const Gradient heroGradientDark = heroGradientLight;

  static const Gradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDeep, primaryDark, primary],
  );

  static const Gradient authHeaderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDeep, primaryDark, primary],
  );

  static const Gradient connectedGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primary],
  );

  // Neutral plum gradient.
  static const Gradient navyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundWarm, background],
  );

  static const Gradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primaryBright],
  );

  // ── Dark aliases ─────────────────────────────────────────────────────────

  static const Color darkBackground = background;
  static const Color darkBackgroundWarm = backgroundWarm;
  static const Color darkSurface = surface;
  static const Color darkSurfaceMuted = surfaceMuted;
  static const Color darkSurfaceElevated = surfaceElevated;
  static const Color darkSurfaceSunken = surfaceSunken;
  static const Color darkSurfaceBase = surfaceBase;
  static const Color darkSurfaceRaised = surfaceRaised;
  static const Color darkSurfaceFloating = surfaceFloating;

  static const Color darkInk = ink;
  static const Color darkInkMuted = inkMuted;
  static const Color darkInkSoft = inkSoft;

  static const Color darkBorder = border;
  static const Color darkBorderFocus = borderFocus;
  static const Color darkGridLine = Color(0x122A3140);

  // ── ColorScheme Builders ─────────────────────────────────────────────────

  static ColorScheme lightScheme() {
    return ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: primary,
      onPrimary: ink,
      primaryContainer: primaryDeep,
      onPrimaryContainer: primaryBright,
      secondary: secondary,
      onSecondary: ink,
      secondaryContainer: secondaryLight,
      onSecondaryContainer: ink,
      tertiary: tertiary,
      onTertiary: ink,
      error: errorDark,
      onError: background,
      surface: surface,
      onSurface: ink,
      surfaceContainerHighest: surfaceMuted,
      onSurfaceVariant: inkMuted,
      outline: border,
      outlineVariant: const Color(0xFF2A1F4A),
      shadow: const Color(0xFF060410),
      scrim: const Color(0xFF0E0818),
    );
  }

  // darkScheme() kept for compile compatibility — returns same dark scheme.
  static ColorScheme darkScheme() => lightScheme();
}

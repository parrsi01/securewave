import 'package:flutter/material.dart';

/// SecureWave color system — pure purple dark-to-light hue.
///
/// Dark plum (#120C1F) → neon purple (#7A5CFF) → lavender white (#E8E0FF).
/// No blue/cyan. Tertiary pink (#FF2BD6) as accent.
class AppColors {
  AppColors._();

  // ── Primary (Neon Purple) ─────────────────────────────────────────────────

  static const Color primary = Color(0xFF7A5CFF);
  static const Color primaryDark = Color(0xFF5A3FCC);
  static const Color primaryDeep = Color(0xFF24183E);
  static const Color primaryBright = Color(0xFFB794FF); // light lavender
  static const Color primaryLight = Color(0xFF2D2150); // container on dark

  static const Color primaryGhost = Color(0x147A5CFF);
  static const Color primaryWash = Color(0x1E7A5CFF);

  // ── Secondary (Light Purple / Lavender) ───────────────────────────────────
  // No cyan — secondary is a lighter shade of purple

  static const Color secondary = Color(0xFFB794FF); // light lavender
  static const Color secondaryDark = Color(0xFF9A72FF); // mid lavender
  static const Color secondaryLight = Color(0xFF241A3A);
  static const Color secondaryWash = Color(0x14B794FF);

  // ── Tertiary (Neon Pink — accent only) ────────────────────────────────────

  static const Color tertiary = Color(0xFFFF2BD6);
  static const Color tertiaryDark = Color(0xFFCC1FAB);

  // ── Semantic / Status ─────────────────────────────────────────────────────

  static const Color success = Color(0xFF9A72FF); // mid-lavender for connected
  static const Color successDark = Color(0xFF7A5CFF);
  static const Color warning = Color(0xFFFFB454);
  static const Color warningDark = Color(0xFFD68910);
  static const Color error = Color(0xFFFF4D6A);
  static const Color errorDark = Color(0xFFCC3355);

  static const Color successLight = Color(0xFF1E1535);
  static const Color warningLight = Color(0xFF221A0D);
  static const Color errorLight = Color(0xFF220D12);

  // ── Surfaces (dark plum ramp) ─────────────────────────────────────────────

  static const Color background = Color(0xFF0E0818); // deepest dark plum
  static const Color backgroundWarm = Color(0xFF160F26); // slightly warmer
  static const Color surface = Color(0xFF130B22);
  static const Color surfaceMuted = Color(0xFF1E1535);
  static const Color surfaceElevated = Color(0xFF291C47);

  // ── Text (lavender-white ramp) ────────────────────────────────────────────

  static const Color ink = Color(0xFFEDE6FF); // near-white with purple tint
  static const Color inkMuted = Color(0xFFBAAFDD);
  static const Color inkSoft = Color(0xFF8070A8);

  // ── Borders ───────────────────────────────────────────────────────────────

  static const Color border = Color(0xFF3D2D66);
  static const Color borderFocus = primary;

  // ── Ambient Glows ─────────────────────────────────────────────────────────

  static const Color ambientGlowPrimary = Color(0x1E7A5CFF); // purple glow
  static const Color ambientGlowSecondary = Color(0x12B794FF); // lavender glow
  static const Color ambientGlowTertiary = Color(0x0EFF2BD6); // pink accent

  // ── Glass Tokens ─────────────────────────────────────────────────────────

  static Color get glassFillLight =>
      const Color(0xFF1A1130).withValues(alpha: 0.88);

  static Color get glassFillDark =>
      const Color(0xFF0E0818).withValues(alpha: 0.88);

  static Color get glassBorderLight =>
      const Color(0xFF7A5CFF).withValues(alpha: 0.30);

  static Color get glassBorderDark =>
      const Color(0xFF7A5CFF).withValues(alpha: 0.30);

  // ── Gradient Presets ─────────────────────────────────────────────────────

  static const Gradient heroGradientLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [background, backgroundWarm],
    stops: [0.0, 1.0],
  );

  static const Gradient heroGradientDark = heroGradientLight;

  /// Dark purple → neon purple → light lavender
  static const Gradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primary, primaryBright],
  );

  static const Gradient authHeaderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDeep, primaryDark, primary],
  );

  /// Connected state: neon purple → lavender
  static const Gradient connectedGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryBright],
  );

  // Neutral plum gradient.
  static const Gradient navyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundWarm, background],
  );

  /// Lavender accent gradient
  static const Gradient lavenderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [secondary, secondaryDark],
  );

  // ── Dark aliases ─────────────────────────────────────────────────────────

  static const Color darkBackground = background;
  static const Color darkBackgroundWarm = backgroundWarm;
  static const Color darkSurface = surface;
  static const Color darkSurfaceMuted = surfaceMuted;
  static const Color darkSurfaceElevated = surfaceElevated;

  static const Color darkInk = ink;
  static const Color darkInkMuted = inkMuted;
  static const Color darkInkSoft = inkSoft;

  static const Color darkBorder = border;
  static const Color darkBorderFocus = borderFocus;
  static const Color darkGridLine = Color(0x127A5CFF);

  // ── ColorScheme Builders ─────────────────────────────────────────────────

  static ColorScheme lightScheme() {
    return ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: primary,
      onPrimary: ink,
      primaryContainer: primaryLight,
      onPrimaryContainer: primaryBright,
      secondary: secondary,
      onSecondary: background,
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
      outlineVariant: const Color(0xFF2E1F52),
      shadow: const Color(0xFF0A0612),
      scrim: const Color(0xFF0E0818),
    );
  }

  // darkScheme() kept for compile compatibility — returns same dark scheme.
  static ColorScheme darkScheme() => lightScheme();
}

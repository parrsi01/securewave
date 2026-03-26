import 'package:flutter/material.dart';

/// SecureWave color system — near-black surfaces with blue, pink, and purple accents.
class AppColors {
  AppColors._();

  // ── Brand Primary (Electric Blue) ───────────────────────────────────────

  static const Color primary = Color(0xFF4F8DFF);
  static const Color primaryDark = Color(0xFF345FC7);
  static const Color primaryDeep = Color(0xFF1F347A);
  static const Color primaryBright = Color(0xFF7BB8FF);
  static const Color primaryLight = Color(0xFFDCE9FF);

  /// Translucent blue overlay
  static const Color primaryGhost = Color(0x147BB8FF);

  // ── Secondary (Neon Pink / Purple) ────────────────────────────────────

  static const Color secondary = Color(0xFFFF5CF4);
  static const Color secondaryDark = Color(0xFF9B6BFF);
  static const Color secondaryLight = Color(0xFFF7E2FF);

  // ── Semantic / Status ─────────────────────────────────────────────────

  static const Color success = primaryBright;
  static const Color successDark = primaryDark;
  static const Color warning = Color(0xFFFFAB00);
  static const Color warningDark = Color(0xFFC26B1F);
  static const Color error = Color(0xFFFF7272);
  static const Color errorDark = Color(0xFFB3261E);

  static const Color successLight = primaryLight;
  static const Color warningLight = Color(0xFFF9E5D0);
  static const Color errorLight = Color(0xFFF5D6D4);

  // ── Light Mode Surfaces ────────────────────────────────────────────────

  static const Color background = Color(0xFFF7F8FF);
  static const Color backgroundWarm = Color(0xFFF1F2FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF2F5F7);
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  // ── Light Mode Text ────────────────────────────────────────────────────

  static const Color ink = Color(0xFF12182D);
  static const Color inkMuted = Color(0xFF55607D);
  static const Color inkSoft = Color(0xFF8690AE);

  // ── Light Mode Borders ─────────────────────────────────────────────────

  static const Color border = Color(0xFFD7DDF4);
  static const Color borderFocus = primary;

  // ── Dark Mode Surfaces (deep navy) ──────────────────────────────────

  static const Color darkBackground = Color(0xFF050711);
  static const Color darkBackgroundWarm = Color(0xFF090D1A);
  static const Color darkSurface = Color(0xFF111728);
  static const Color darkSurfaceMuted = Color(0xFF141C31);
  static const Color darkSurfaceElevated = Color(0xFF181F38);

  // ── Dark Mode Text ─────────────────────────────────────────────────────

  static const Color darkInk = Color(0xFFF2F5FF);
  static const Color darkInkMuted = Color(0xFFAAB5D6);
  static const Color darkInkSoft = Color(0xFF727A99);

  // ── Dark Mode Borders ──────────────────────────────────────────────────

  static const Color darkBorder = Color(0xFF232B45);
  static const Color darkBorderFocus = primaryBright;

  // ── Glassmorphism Tokens ──────────────────────────────────────────────

  /// Frosted glass fill — light mode
  static Color get glassFillLight =>
      const Color(0xFFFFFFFF).withValues(alpha: 0.72);

  /// Frosted glass fill — dark mode
  static Color get glassFillDark =>
      const Color(0xFF121E32).withValues(alpha: 0.80);

  /// Glass border — light mode
  static Color get glassBorderLight =>
      const Color(0xFFFFFFFF).withValues(alpha: 0.4);

  /// Glass border — dark mode
  static Color get glassBorderDark =>
      const Color(0xFF7BB8FF).withValues(alpha: 0.16);

  // ── Gradient Presets ──────────────────────────────────────────────────

  /// Hero radial gradient (light mode) — centered on the connection ring
  static const Gradient heroGradientLight = RadialGradient(
    center: Alignment.topCenter,
    radius: 1.2,
    colors: [Color(0xFFEFF5FF), Color(0xFFF9F1FF)],
    stops: [0.0, 1.0],
  );

  /// Hero radial gradient (dark mode)
  static const Gradient heroGradientDark = RadialGradient(
    center: Alignment.topCenter,
    radius: 1.2,
    colors: [Color(0xFF1A1830), Color(0xFF050711)],
    stops: [0.0, 1.0],
  );

  /// Deep neon gradient — primary CTA (connect button, avatar, badges)
  static const Gradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryBright, secondaryDark],
  );

  /// Auth screen header gradient (dark login page)
  static const Gradient authHeaderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondaryDark],
  );

  /// Connected state gradient — electric blue into neon pink
  static const Gradient connectedGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryBright, secondaryDark],
  );

  /// Navy depth gradient for shells / backgrounds
  static const Gradient navyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [darkBackgroundWarm, darkBackground],
  );

  /// Cyan accent gradient
  static const Gradient cyanGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [secondaryDark, secondary],
  );

  // ── ColorScheme Builders ──────────────────────────────────────────────

  static ColorScheme lightScheme() {
    return ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: primaryDeep,
      onPrimary: Colors.white,
      primaryContainer: primaryLight,
      onPrimaryContainer: primaryDeep,
      secondary: secondary,
      onSecondary: ink,
      secondaryContainer: secondaryLight,
      onSecondaryContainer: const Color(0xFF3D1D66),
      error: errorDark,
      onError: Colors.white,
      surface: surface,
      onSurface: ink,
      surfaceContainerHighest: surfaceMuted,
      onSurfaceVariant: inkMuted,
      outline: border,
      outlineVariant: const Color(0xFFEDF0F3),
      shadow: ink,
      scrim: ink,
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
      outlineVariant: const Color(0xFF1C2440),
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

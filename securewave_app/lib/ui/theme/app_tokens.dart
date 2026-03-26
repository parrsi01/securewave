import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Design tokens for the shared SecureWave dark theme.
///
/// Covers: spacing, border radius, elevation/shadow, glow effects,
/// animation durations, and animation curves.
class AppTokens {
  AppTokens._();

  // ── Spacing Scale (4dp base) ──────────────────────────────────────────────

  static const double sp4 = 4;
  static const double sp8 = 8;
  static const double sp12 = 12;
  static const double sp16 = 16;
  static const double sp24 = 24;
  static const double sp32 = 32;
  static const double sp48 = 48;
  static const double sp64 = 64;

  // Semantic aliases
  static const double paddingXS = sp4;
  static const double paddingS = sp8;
  static const double paddingM = sp16;
  static const double paddingL = sp24;
  static const double paddingXL = sp32;

  static const double gapXS = sp4;
  static const double gapS = sp8;
  static const double gapM = sp12;
  static const double gapL = sp16;
  static const double gapXL = sp24;

  // ── Border Radius ─────────────────────────────────────────────────────────

  static const double radiusSmall = 4;
  static const double radiusMedium = 8;
  static const double radiusLarge = 16;
  static const double radiusCard = 12;
  static const double radiusPill = 999;

  static const BorderRadius brSmall =
      BorderRadius.all(Radius.circular(radiusSmall));
  static const BorderRadius brMedium =
      BorderRadius.all(Radius.circular(radiusMedium));
  static const BorderRadius brLarge =
      BorderRadius.all(Radius.circular(radiusLarge));
  static const BorderRadius brCard =
      BorderRadius.all(Radius.circular(radiusCard));
  static const BorderRadius brPill =
      BorderRadius.all(Radius.circular(radiusPill));

  // ── Elevation — standard Material shadows ─────────────────────────────────

  static const List<BoxShadow> shadowLow = [
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> shadowMedium = [
    BoxShadow(
      color: Color(0x4D000000),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> shadowHigh = [
    BoxShadow(
      color: Color(0x66000000),
      blurRadius: 32,
      offset: Offset(0, 8),
    ),
  ];

  // ── Glow Effects — softened BoxShadow lists ───────────────────────────────

  /// Primary accent glow for CTA surfaces and connected state chrome.
  static const List<BoxShadow> glowPrimary = [
    BoxShadow(
      color: HtbColors.glowPrimarySoft,
      blurRadius: 18,
      spreadRadius: 1,
    ),
    BoxShadow(
      color: HtbColors.glowPrimary,
      blurRadius: 6,
      spreadRadius: 0,
    ),
  ];

  /// Intensified primary accent glow for pressed and highly active states.
  static const List<BoxShadow> glowPrimaryIntense = [
    BoxShadow(
      color: HtbColors.glowPrimary,
      blurRadius: 26,
      spreadRadius: 2,
    ),
    BoxShadow(
      color: HtbColors.accentPrimary,
      blurRadius: 8,
      spreadRadius: 0,
    ),
  ];

  /// Subtle primary accent glow for idle highlighted surfaces.
  static const List<BoxShadow> glowPrimarySoft = [
    BoxShadow(
      color: HtbColors.glowPrimarySoft,
      blurRadius: 12,
      spreadRadius: 0,
    ),
  ];

  /// Secondary accent glow for pink/purple emphasis.
  static const List<BoxShadow> glowSecondary = [
    BoxShadow(
      color: HtbColors.glowSecondary,
      blurRadius: 14,
      spreadRadius: 0,
    ),
  ];

  /// Red glow — error / disconnected state
  static const List<BoxShadow> glowRed = [
    BoxShadow(
      color: HtbColors.glowRed,
      blurRadius: 14,
      spreadRadius: 0,
    ),
  ];

  /// Amber glow — connecting state
  static const List<BoxShadow> glowAmber = [
    BoxShadow(
      color: HtbColors.glowAmber,
      blurRadius: 14,
      spreadRadius: 0,
    ),
  ];

  // ── Animation Durations ───────────────────────────────────────────────────

  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationNormal = Duration(milliseconds: 250);
  static const Duration durationSlow = Duration(milliseconds: 400);
  static const Duration durationXSlow = Duration(milliseconds: 600);

  /// Pulse loop for connecting state
  static const Duration durationPulse = Duration(milliseconds: 1400);

  /// Glow breathe cycle
  static const Duration durationGlowCycle = Duration(milliseconds: 2000);

  // ── Animation Curves ──────────────────────────────────────────────────────

  static const Curve curveDefault = Curves.easeOutCubic;
  static const Curve curveEnter = Curves.easeOutCubic;
  static const Curve curveExit = Curves.easeInCubic;
  static const Curve curveSharp = Curves.fastOutSlowIn;
  static const Curve curveBounce = Curves.elasticOut;
  static const Curve curvePulse = Curves.easeInOut;

  // ── Button Sizes ──────────────────────────────────────────────────────────

  static const double buttonHeightM = 48;
  static const double buttonHeightL = 56;
  static const double buttonMinWidth = 120;

  // ── Icon Sizes ────────────────────────────────────────────────────────────

  static const double iconXS = 14;
  static const double iconS = 18;
  static const double iconM = 22;
  static const double iconL = 28;
  static const double iconXL = 36;

  // ── Misc ──────────────────────────────────────────────────────────────────

  /// Backdrop blur sigma used on glass panels
  static const double blurSigma = 14;

  /// Border width for neon-lit containers
  static const double neonBorderWidth = 1.25;

  /// Default border width
  static const double borderWidth = 1;
}

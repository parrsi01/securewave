import 'package:flutter/material.dart';

import '../design/app_animations.dart';
import 'app_colors.dart';

/// Design tokens for the shared SecureWave theme.
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
      color: Color(0x22000000),
      blurRadius: 10,
      offset: Offset(0, 3),
    ),
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  static const List<BoxShadow> shadowMedium = [
    BoxShadow(
      color: Color(0x30000000),
      blurRadius: 18,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color(0x16000000),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> shadowHigh = [
    BoxShadow(
      color: Color(0x3D000000),
      blurRadius: 28,
      offset: Offset(0, 14),
    ),
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 10,
      offset: Offset(0, 4),
    ),
  ];

  // ── Glow Effects — reserved for interactive states ───────────────────────

  /// Neon purple glow — primary CTA, connected ring
  static const List<BoxShadow> glowGreen = [
    BoxShadow(
      color: HtbColors.glowGreenSoft,
      blurRadius: 14,
      spreadRadius: 0,
    ),
    BoxShadow(
      color: HtbColors.glowGreen,
      blurRadius: 6,
      spreadRadius: 0,
    ),
  ];

  /// Neon purple glow — intense (pressed/active state)
  static const List<BoxShadow> glowGreenIntense = [
    BoxShadow(
      color: HtbColors.glowGreen,
      blurRadius: 20,
      spreadRadius: 0,
    ),
    BoxShadow(
      color: HtbColors.neonGreen,
      blurRadius: 8,
      spreadRadius: 0,
    ),
  ];

  /// Neon purple glow — subtle (idle connected)
  static const List<BoxShadow> glowGreenSoft = [
    BoxShadow(
      color: HtbColors.glowGreenSoft,
      blurRadius: 10,
      spreadRadius: 0,
    ),
  ];

  /// Lavender glow — secondary highlights
  static const List<BoxShadow> glowCyan = [
    BoxShadow(
      color: HtbColors.glowCyan,
      blurRadius: 12,
      spreadRadius: 0,
    ),
  ];

  /// Neon purple glow — semantic alias for primary
  static const List<BoxShadow> glowPrimary = [
    BoxShadow(
      color: HtbColors.glowPrimarySoft,
      blurRadius: 14,
      spreadRadius: 0,
    ),
    BoxShadow(
      color: HtbColors.glowPrimary,
      blurRadius: 6,
      spreadRadius: 0,
    ),
  ];

  /// Neon purple glow — soft variant
  static const List<BoxShadow> glowPrimarySoft = [
    BoxShadow(
      color: HtbColors.glowPrimarySoft,
      blurRadius: 10,
      spreadRadius: 0,
    ),
  ];

  /// Red glow — error / disconnected state
  static const List<BoxShadow> glowRed = [
    BoxShadow(
      color: HtbColors.glowRed,
      blurRadius: 12,
      spreadRadius: 0,
    ),
  ];

  /// Amber glow — connecting state
  static const List<BoxShadow> glowAmber = [
    BoxShadow(
      color: HtbColors.glowAmber,
      blurRadius: 12,
      spreadRadius: 0,
    ),
  ];

  // ── Animation Durations ───────────────────────────────────────────────────

  static const Duration durationFast = AppAnimations.durationFast;
  static const Duration durationNormal = AppAnimations.durationNormal;
  static const Duration durationSlow = AppAnimations.durationSlow;
  static const Duration durationXSlow = AppAnimations.durationXSlow;

  /// Pulse loop for connecting state
  static const Duration durationPulse = AppAnimations.glowPulseDuration;

  /// Glow breathe cycle
  static const Duration durationGlowCycle = AppAnimations.glowPulseDuration;

  // ── Animation Curves ──────────────────────────────────────────────────────

  static const Curve curveDefault = AppAnimations.curveDefault;
  static const Curve curveEnter = AppAnimations.curveEnter;
  static const Curve curveExit = AppAnimations.curveExit;
  static const Curve curveSharp = AppAnimations.curveSharp;
  static const Curve curveBounce = AppAnimations.curveBounce;
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
  static const double blurSigma = 12;

  /// Border width for neon-lit containers
  static const double neonBorderWidth = 1.25;

  /// Default border width
  static const double borderWidth = 1;
}

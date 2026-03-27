import 'package:flutter/animation.dart';

/// SecureWave animation constants and curves.
///
/// Standard [Duration], [Curve], and motion constants only.
/// Values stay short and restrained to keep the UI responsive.
class AppAnimations {
  AppAnimations._();

  // ── Durations ──────────────────────────────────────────────────────────

  static const Duration durationFast = Duration(milliseconds: 140);
  static const Duration durationNormal = Duration(milliseconds: 220);
  static const Duration durationMedium = Duration(milliseconds: 320);
  static const Duration durationSlow = Duration(milliseconds: 420);
  static const Duration durationXSlow = Duration(milliseconds: 560);

  static const Duration durationHover = Duration(milliseconds: 180);
  static const Duration durationPress = durationFast;
  static const Duration durationSurfaceEnter = durationMedium;

  // ── Curves ─────────────────────────────────────────────────────────────

  static const Curve curveDefault = Cubic(0.2, 0.8, 0.2, 1.0);
  static const Curve curveEnter = Cubic(0.16, 1.0, 0.3, 1.0);
  static const Curve curveExit = Curves.easeInCubic;
  static const Curve curveSpring = Curves.elasticOut;
  static const Curve curveBounce = Curves.bounceOut;
  static const Curve curveSharp = Cubic(0.2, 0.0, 0.0, 1.0);

  // ── Shared Motion Values ───────────────────────────────────────────────

  static const double buttonHoverScale = 1.01;
  static const double buttonPressScale = 0.975;
  static const double pageSlideOffset = 0.018;
  static const double surfaceSlideOffset = 0.05;

  // ── Connection Ring ────────────────────────────────────────────────────

  static const Duration connectionTransition = Duration(milliseconds: 320);
  static const double connectionButtonScale = 0.94;
  static const Duration glowPulseDuration = Duration(milliseconds: 1800);
  static const Duration ringRotationDuration = Duration(milliseconds: 1400);

  // ── List & Card ────────────────────────────────────────────────────────

  static const Duration listStagger = Duration(milliseconds: 40);
  static const Duration cardRipple = Duration(milliseconds: 280);
  static const Duration favoriteToggle = Duration(milliseconds: 200);
  static const Duration checkmarkFade = Duration(milliseconds: 160);

  // ── Page Transitions ───────────────────────────────────────────────────

  static const Duration pageEnter = Duration(milliseconds: 300);
  static const Duration pageExit = Duration(milliseconds: 200);
}

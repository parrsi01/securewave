import 'package:flutter/animation.dart';

/// SecureWave animation constants and curves — v2.
///
/// Core timing tokens used throughout the app. For advanced spring configs
/// and page transition helpers, see app_motion.dart.
class AppAnimations {
  AppAnimations._();

  // ── Durations ────────────────────────────────────────────────────────────

  static const Duration durationFast    = Duration(milliseconds: 120);
  static const Duration durationNormal  = Duration(milliseconds: 250);
  static const Duration durationMedium  = Duration(milliseconds: 350);
  static const Duration durationSlow    = Duration(milliseconds: 450);
  static const Duration durationXSlow   = Duration(milliseconds: 600);

  // ── Curves ───────────────────────────────────────────────────────────────

  static const Curve curveDefault  = Curves.easeOutCubic;
  static const Curve curveEnter    = Curves.easeOutCubic;
  static const Curve curveExit     = Curves.easeInCubic;
  static const Curve curveSpring   = Curves.elasticOut;
  static const Curve curveBounce   = Curves.bounceOut;
  static const Curve curveSharp    = Curves.fastOutSlowIn;

  // ── Connection Ring ──────────────────────────────────────────────────────

  static const Duration connectionTransition = Duration(milliseconds: 320);
  static const double   connectionButtonScale = 0.94;
  static const Duration glowPulseDuration     = Duration(milliseconds: 1800);
  static const Duration ringRotationDuration  = Duration(milliseconds: 1400);

  // ── List & Card ──────────────────────────────────────────────────────────

  static const Duration listStagger    = Duration(milliseconds: 40);
  static const Duration cardRipple     = Duration(milliseconds: 280);
  static const Duration favoriteToggle = Duration(milliseconds: 200);
  static const Duration checkmarkFade  = Duration(milliseconds: 160);

  // ── Page Transitions ─────────────────────────────────────────────────────

  static const Duration pageEnter = Duration(milliseconds: 300);
  static const Duration pageExit  = Duration(milliseconds: 200);
}

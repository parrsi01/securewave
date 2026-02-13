import 'package:flutter/animation.dart';

/// SecureWave animation constants and curves.
///
/// Provides consistent animation timing and easing throughout the app.
class AppAnimations {
  AppAnimations._();

  // ── Animation Durations ─────────────────────────────────────────────────

  /// Fast animation (120ms) - Micro-interactions, quick feedback
  static const Duration durationFast = Duration(milliseconds: 120);

  /// Normal animation (250ms) - Standard transitions, state changes
  static const Duration durationNormal = Duration(milliseconds: 250);

  /// Slow animation (400ms) - Complex transitions, page changes
  static const Duration durationSlow = Duration(milliseconds: 400);

  // ── Animation Curves ────────────────────────────────────────────────────

  /// Default curve - Smooth ease-out cubic (most common)
  static const Curve curveDefault = Curves.easeOutCubic;

  /// Enter curve - Ease-out for entering elements
  static const Curve curveEnter = Curves.easeOut;

  /// Exit curve - Ease-in for exiting elements
  static const Curve curveExit = Curves.easeIn;

  // ── Connection Button Animations ────────────────────────────────────────

  /// Connection button state transition duration (300ms)
  static const Duration connectionTransition = Duration(milliseconds: 300);

  /// Connection button scale on press (95%)
  static const double connectionButtonScale = 0.95;

  /// Glow pulse duration for connected state (2 seconds)
  static const Duration glowPulseDuration = Duration(seconds: 2);

  // ── List & Card Animations ──────────────────────────────────────────────

  /// Stagger delay for list items (50ms)
  static const Duration listStagger = Duration(milliseconds: 50);

  /// Card ripple duration (300ms)
  static const Duration cardRipple = Duration(milliseconds: 300);

  // ── Micro-Interactions ──────────────────────────────────────────────────

  /// Favorite star toggle duration (200ms)
  static const Duration favoriteToggle = Duration(milliseconds: 200);

  /// Checkmark fade-in duration (150ms)
  static const Duration checkmarkFade = Duration(milliseconds: 150);
}

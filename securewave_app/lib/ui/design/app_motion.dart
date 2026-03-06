import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_animations.dart';

/// SecureWave motion vocabulary — v2.
///
/// Spring configs, hero transition settings, stagger helpers, and
/// platform-specific page transition builders. This complements
/// AppAnimations (which holds raw timing constants).
class AppMotion {
  AppMotion._();

  // ── Implicit Animation Configs ──────────────────────────────────────────

  /// Standard implicit animation (size, opacity, position)
  static const Duration standard = AppAnimations.durationNormal;

  /// Snappy micro-interaction (toggles, checkbox, icon swaps)
  static const Duration micro = AppAnimations.durationFast;

  /// Expressive motion for hero elements
  static const Duration expressive = AppAnimations.durationMedium;

  /// Slow reveal for page-level content
  static const Duration reveal = AppAnimations.durationSlow;

  // ── Curve Presets ────────────────────────────────────────────────────────

  static const Curve enter = AppAnimations.curveEnter;
  static const Curve exit = AppAnimations.curveExit;
  static const Curve standardCurve = AppAnimations.curveDefault;

  /// Snappy overshoot for icon/fab state changes
  static const Curve emphatic = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Material You decelerate curve
  static const Curve decelerate = Cubic(0.05, 0.7, 0.1, 1.0);

  /// Material You accelerate curve
  static const Curve accelerate = Cubic(0.3, 0.0, 1.0, 1.0);

  // ── Stagger ──────────────────────────────────────────────────────────────

  /// Compute staggered offset for index [i] in a list.
  static Duration stagger(int i, {Duration step = AppAnimations.listStagger}) {
    return step * i;
  }

  // ── Page Transition Builders ─────────────────────────────────────────────

  /// Fade + tiny upward slide — used on Android/Linux/Windows.
  static Widget fadeSlide(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child, {
    bool isFirst = false,
  }) {
    if (isFirst) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.enter,
      reverseCurve: AppMotion.exit,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }

  // ── Hero Flight ──────────────────────────────────────────────────────────

  static const HeroFlightShuttleBuilder logoShuttle = _logoShuttleBuilder;

  static Widget _logoShuttleBuilder(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  ) {
    final hero = flightDirection == HeroFlightDirection.push
        ? toHeroContext.widget
        : fromHeroContext.widget;
    return ScaleTransition(
      scale: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
      child: (hero as Hero).child,
    );
  }

  // ── AnimatedSwitcher Helpers ─────────────────────────────────────────────

  static Widget fadeTransitionBuilder(Widget child, Animation<double> anim) {
    return FadeTransition(opacity: anim, child: child);
  }

  static Widget scaleFadeTransitionBuilder(
      Widget child, Animation<double> anim) {
    return FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1.0).animate(
          CurvedAnimation(parent: anim, curve: AppMotion.decelerate),
        ),
        child: child,
      ),
    );
  }
}

/// Platform-aware fade+slide page transition builder.
class FadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return AppMotion.fadeSlide(
      context,
      animation,
      secondaryAnimation,
      child,
      isFirst: route.isFirst,
    );
  }
}

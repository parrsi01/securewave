import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppUIv1 {
  // ── Palette (unchanged) ──────────────────────────────────────────────
  static const Color background = Color(0xFFF5F7FB);
  static const Color backgroundStrong = Color(0xFFE7EDF3);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF0F4F7);
  static const Color accent = Color(0xFF1B6B68);
  static const Color accentStrong = Color(0xFF0F4F4C);
  static const Color accentSoft = Color(0xFFD5EFEC);
  static const Color accentSun = Color(0xFFF6C14D);
  static const Color success = Color(0xFF1F8F5C);
  static const Color warning = Color(0xFFC26B1F);
  static const Color ink = Color(0xFF0B1F2A);
  static const Color inkMuted = Color(0xFF4A5B66);
  static const Color inkSoft = Color(0xFF72838F);
  static const Color border = Color(0xFFD7E0E7);

  // ── Spacing (8dp grid) ──────────────────────────────────────────────
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;
  static const double space6 = 32;
  static const double space7 = 48;
  static const double space8 = 64;

  // ── Border radii ────────────────────────────────────────────────────
  static const double radiusS = 8;
  static const double radiusM = 12;
  static const double radiusL = 16;
  static const double radiusXL = 20;
  static const double radiusFull = 999;

  // ── Shadows ─────────────────────────────────────────────────────────
  static List<BoxShadow> get shadowSm => [
        BoxShadow(
          color: ink.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];
  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: ink.withValues(alpha: 0.06),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  // ── Animation constants ─────────────────────────────────────────────
  static const Duration durationFast = Duration(milliseconds: 120);
  static const Duration durationNormal = Duration(milliseconds: 250);
  static const Duration durationSlow = Duration(milliseconds: 400);
  static const Curve curveDefault = Curves.easeOutCubic;
  static const Curve curveEnter = Curves.easeOut;
  static const Curve curveExit = Curves.easeIn;

  // ── Layout constraints ──────────────────────────────────────────────
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double authMaxWidth = 440;
  static const double contentMaxWidth = 720;

  // ── Helpers ─────────────────────────────────────────────────────────

  /// True when running on Apple platforms (Cupertino style preferred).
  static bool get isApplePlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: accent,
      onPrimary: Colors.white,
      secondary: accentSun,
      onSecondary: ink,
      error: warning,
      onError: Colors.white,
      surface: surface,
      onSurface: ink,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
    );

    // Use Google Fonts on iOS/Android/Web, but system fonts on Linux
    // to avoid Skia rendering crashes
    final textTheme = (!kIsWeb && Platform.isLinux)
        ? base.textTheme
        : GoogleFonts.manropeTextTheme(base.textTheme);

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: textTheme.copyWith(
        headlineMedium: const TextStyle(fontWeight: FontWeight.w700, color: ink),
        titleLarge: const TextStyle(fontWeight: FontWeight.w700, color: ink),
        titleMedium: const TextStyle(fontWeight: FontWeight.w600, color: ink),
        bodyLarge: const TextStyle(color: ink),
        bodyMedium: const TextStyle(color: inkMuted),
        bodySmall: const TextStyle(color: inkSoft),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: ink,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXL),
          side: const BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusL),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusL),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusL),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: inkSoft),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusFull)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusFull)),
          side: const BorderSide(color: border),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      dividerColor: border,
      listTileTheme: const ListTileThemeData(
        iconColor: accent,
        textColor: ink,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: accentSoft,
        backgroundColor: surface,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: accent);
          }
          return const IconThemeData(color: inkSoft);
        }),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        indicatorColor: accentSoft,
        backgroundColor: surface,
        elevation: 0,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: _FadeSlidePageTransitionsBuilder(),
          TargetPlatform.linux: _FadeSlidePageTransitionsBuilder(),
          TargetPlatform.windows: _FadeSlidePageTransitionsBuilder(),
          TargetPlatform.fuchsia: _FadeSlidePageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Fade + slight vertical slide transition for non-Apple platforms.
class _FadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppUIv1.curveEnter,
      reverseCurve: AppUIv1.curveExit,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

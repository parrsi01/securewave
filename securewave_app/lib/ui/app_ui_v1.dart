import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppUIv1 {
  // SecureWave premium dark brand palette.
  static const Color background = Color(0xFF020711);
  static const Color backgroundStrong = Color(0xFF050D1C);
  static const Color surface = Color(0xFF081426);
  static const Color surfaceElevated = Color(0xFF0D1B32);
  static const Color surfaceMuted = Color(0xFF10233D);
  static const Color surfaceGlass = Color(0xB30A172B);
  static const Color accent = Color(0xFF10B7FF);
  static const Color accentStrong = Color(0xFF4C7DFF);
  static const Color accentCyan = Color(0xFF00D5FF);
  static const Color accentTeal = Color(0xFF15E3C3);
  static const Color accentViolet = Color(0xFF8B5CF6);
  static const Color accentSoft = Color(0x3320C7FF);
  static const Color accentSun = Color(0xFFFFC857);
  static const Color success = Color(0xFF17F2A4);
  static const Color warning = Color(0xFFFFB454);
  static const Color danger = Color(0xFFFF5470);
  static const Color ink = Color(0xFFF4F8FF);
  static const Color inkMuted = Color(0xFFB5C7E4);
  static const Color inkSoft = Color(0xFF7890B4);
  static const Color border = Color(0xFF1D3558);
  static const Color borderStrong = Color(0xFF2E5D91);

  static const Gradient brandGradient = LinearGradient(
    colors: [accentStrong, accentCyan, accentTeal],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient violetGradient = LinearGradient(
    colors: [accentStrong, accentViolet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // 8dp grid with compact affordances for laptop screens.
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;
  static const double space6 = 32;
  static const double space7 = 48;
  static const double space8 = 64;

  static const double radiusS = 8;
  static const double radiusM = 12;
  static const double radiusL = 16;
  static const double radiusXL = 20;
  static const double radiusFull = 999;

  static List<BoxShadow> get shadowSm => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.20),
          blurRadius: 12,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.32),
          blurRadius: 24,
          offset: const Offset(0, 16),
        ),
      ];

  static List<BoxShadow> glow(Color color, {double opacity = 0.20}) => [
        BoxShadow(
          color: color.withValues(alpha: opacity),
          blurRadius: 28,
          spreadRadius: -8,
        ),
      ];

  static const Duration durationFast = Duration(milliseconds: 140);
  static const Duration durationNormal = Duration(milliseconds: 260);
  static const Duration durationSlow = Duration(milliseconds: 520);
  static const Duration durationScan = Duration(milliseconds: 1400);
  static const Curve curveDefault = Curves.easeOutCubic;
  static const Curve curveEnter = Curves.easeOutCubic;
  static const Curve curveExit = Curves.easeInCubic;
  static const Curve curveEmphasis = Curves.easeInOutCubicEmphasized;

  static const double mobileBreakpoint = 640;
  static const double tabletBreakpoint = 960;
  static const double desktopBreakpoint = 1180;
  static const double authMaxWidth = 1080;
  static const double authPanelWidth = 440;
  static const double contentMaxWidth = 1180;
  static const double narrowContentMaxWidth = 760;

  static bool get isApplePlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  static ThemeData theme() {
    const scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: Color(0xFF00111D),
      secondary: accentTeal,
      onSecondary: Color(0xFF001612),
      error: danger,
      onError: Colors.white,
      surface: surface,
      onSurface: ink,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
    );

    final textTheme = (!kIsWeb && Platform.isLinux)
        ? base.textTheme
        : GoogleFonts.manropeTextTheme(base.textTheme);

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: textTheme.copyWith(
        displaySmall: const TextStyle(
          fontWeight: FontWeight.w800,
          color: ink,
          height: 1.02,
          letterSpacing: 0,
        ),
        headlineMedium: const TextStyle(
          fontWeight: FontWeight.w800,
          color: ink,
          height: 1.08,
          letterSpacing: 0,
        ),
        headlineSmall: const TextStyle(
          fontWeight: FontWeight.w800,
          color: ink,
          height: 1.12,
          letterSpacing: 0,
        ),
        titleLarge: const TextStyle(
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: 0,
        ),
        titleMedium: const TextStyle(
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: 0,
        ),
        titleSmall: const TextStyle(
          fontWeight: FontWeight.w700,
          color: inkMuted,
          letterSpacing: 0,
        ),
        bodyLarge: const TextStyle(color: ink, height: 1.45, letterSpacing: 0),
        bodyMedium: const TextStyle(
          color: inkMuted,
          height: 1.45,
          letterSpacing: 0,
        ),
        bodySmall: const TextStyle(
          color: inkSoft,
          height: 1.35,
          letterSpacing: 0,
        ),
        labelLarge: const TextStyle(
          fontWeight: FontWeight.w800,
          color: ink,
          letterSpacing: 0,
        ),
        labelMedium: const TextStyle(
          fontWeight: FontWeight.w700,
          color: inkMuted,
          letterSpacing: 0,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: ink,
      ),
      cardTheme: CardThemeData(
        color: surfaceGlass,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusL),
          side: const BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated.withValues(alpha: 0.72),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: const BorderSide(color: accentCyan, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: const BorderSide(color: danger),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        hintStyle: const TextStyle(color: inkSoft),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accentCyan,
          foregroundColor: const Color(0xFF00121C),
          disabledBackgroundColor: surfaceMuted,
          disabledForegroundColor: inkSoft,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusM),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusM),
          ),
          side: const BorderSide(color: borderStrong),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentCyan,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceMuted,
        selectedColor: accentSoft,
        side: const BorderSide(color: border),
        labelStyle: const TextStyle(
          color: inkMuted,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
        ),
      ),
      dividerColor: border,
      listTileTheme: const ListTileThemeData(
        iconColor: accentCyan,
        textColor: ink,
        subtitleTextStyle: TextStyle(color: inkSoft, height: 1.35),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected) ? accentTeal : inkSoft;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? accentTeal.withValues(alpha: 0.30)
              : surfaceMuted;
        }),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: accentSoft,
        backgroundColor: backgroundStrong.withValues(alpha: 0.96),
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: accentCyan);
          }
          return const IconThemeData(color: inkSoft);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected) ? accentCyan : inkSoft,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          );
        }),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        indicatorColor: accentSoft,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedIconTheme: IconThemeData(color: accentCyan),
        unselectedIconTheme: IconThemeData(color: inkSoft),
        selectedLabelTextStyle: TextStyle(
          color: ink,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: inkSoft,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
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
          begin: const Offset(0, 0.018),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

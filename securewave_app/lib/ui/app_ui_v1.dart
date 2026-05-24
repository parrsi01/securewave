import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum SecureSurfaceVariant {
  base,
  raised,
  glass,
  accent,
  success,
  warning,
  danger,
}

class AppUIv1 {
  // SecureWave app foundation: graphite surfaces, electric lime actions,
  // seawater status, and warm warning/coral failure states.
  // Keep these legacy names stable while future screens migrate to the
  // richer token helpers below.
  static const Color background = Color(0xFF0B0D0E);
  static const Color backgroundStrong = Color(0xFF0F1213);
  static const Color backgroundElevated = Color(0xFF141819);
  static const Color surface = Color(0xFF161A1B);
  static const Color surfaceRaised = Color(0xFF202526);
  static const Color surfaceMuted = Color(0xFF303738);
  static const Color surfaceGlass = Color(0xFF181D1E);
  static const Color surfaceOverlay = Color(0x18D8FF5F);

  static const Color accent = Color(0xFFD8FF5F);
  static const Color accentStrong = Color(0xFFA7D934);
  static const Color accentSoft = Color(0x33D8FF5F);
  static const Color accentCyan = Color(0xFF53E0B8);
  static const Color accentBlue = Color(0xFF9FAC9A);
  static const Color accentSun = Color(0xFFFFB86B);

  static const Color success = Color(0xFF6BF0B3);
  static const Color warning = Color(0xFFFFC266);
  static const Color danger = Color(0xFFFF6B5F);

  static const Color ink = Color(0xFFF4F7EF);
  static const Color inkMuted = Color(0xFFC1CAB9);
  static const Color inkSoft = Color(0xFF879080);
  static const Color inkDisabled = Color(0xFF5B6258);
  static const Color border = Color(0x2DF4F7EF);
  static const Color borderStrong = Color(0x52D8FF5F);
  static const Color divider = Color(0x1FF4F7EF);

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF0B0D0E),
      Color(0xFF0F1213),
      Color(0xFF0B0D0E),
    ],
    stops: [0, 0.48, 1],
  );

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFE6FF76),
      Color(0xFF53E0B8),
      Color(0xFFFF7A6F),
    ],
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1B2021),
      Color(0xFF151819),
    ],
  );

  static const LinearGradient controlGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFD8FF5F),
      Color(0xFF53E0B8),
    ],
  );

  // Spacing (8dp grid).
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;
  static const double space6 = 32;
  static const double space7 = 48;
  static const double space8 = 64;
  static const double space9 = 88;

  // Border radii. Keep app surfaces compact and utilitarian.
  static const double radiusXS = 6;
  static const double radiusS = 8;
  static const double radiusM = 10;
  static const double radiusL = 10;
  static const double radiusXL = 12;
  static const double radiusXXL = 14;
  static const double radiusFull = 999;
  static const double radiusCard = 8;

  // Stroke, elevation, and glow tokens.
  static const double hairline = 1;
  static const double strokeStrong = 1.5;
  static const double blurGlass = 18;
  static const double elevationLow = 0;
  static const double elevationRaised = 2;

  static List<BoxShadow> get shadowSm => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.18),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ];

  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.22),
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
      ];

  static List<BoxShadow> get glowAccent => [
        BoxShadow(
          color: accent.withValues(alpha: 0.16),
          blurRadius: 14,
          spreadRadius: -8,
        ),
      ];

  static List<BoxShadow> get glowSuccess => [
        BoxShadow(
          color: success.withValues(alpha: 0.14),
          blurRadius: 14,
          spreadRadius: -8,
        ),
      ];

  static List<BoxShadow> get glowDanger => [
        BoxShadow(
          color: danger.withValues(alpha: 0.12),
          blurRadius: 14,
          spreadRadius: -8,
        ),
      ];

  // Motion tokens.
  static const Duration durationInstant = Duration(milliseconds: 80);
  static const Duration durationFast = Duration(milliseconds: 140);
  static const Duration durationNormal = Duration(milliseconds: 240);
  static const Duration durationSlow = Duration(milliseconds: 420);
  static const Curve curveDefault = Curves.easeOutCubic;
  static const Curve curveEnter = Curves.easeOutCubic;
  static const Curve curveExit = Curves.easeInCubic;
  static const Curve curveEmphasized = Curves.easeInOutCubicEmphasized;

  // Responsive layout constraints.
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1200;
  static const double authMaxWidth = 440;
  static const double contentMaxWidth = 720;
  static const double contentWideMaxWidth = 1040;
  static const double shellMaxWidth = 1280;

  static bool isCompactWidth(double width) => width < mobileBreakpoint;

  static bool isMediumWidth(double width) =>
      width >= mobileBreakpoint && width < tabletBreakpoint;

  static bool isExpandedWidth(double width) => width >= tabletBreakpoint;

  static EdgeInsets pagePaddingFor(double width) {
    if (width < mobileBreakpoint) {
      return const EdgeInsets.symmetric(horizontal: space4, vertical: space4);
    }
    if (width < tabletBreakpoint) {
      return const EdgeInsets.symmetric(horizontal: space5, vertical: space5);
    }
    return const EdgeInsets.symmetric(horizontal: space6, vertical: space6);
  }

  static double maxContentWidthFor(double width) {
    if (width < tabletBreakpoint) return contentMaxWidth;
    if (width < desktopBreakpoint) return contentWideMaxWidth;
    return shellMaxWidth;
  }

  static Color statusColorForLabel(String label) {
    final normalized = label.toLowerCase();
    if (normalized.contains('connected') && !normalized.contains('dis')) {
      return success;
    }
    if (normalized.contains('connect') || normalized.contains('sync')) {
      return accentSun;
    }
    if (normalized.contains('error') ||
        normalized.contains('attention') ||
        normalized.contains('unreachable')) {
      return danger;
    }
    if (normalized.contains('warning') ||
        normalized.contains('setup') ||
        normalized.contains('unavailable')) {
      return warning;
    }
    return inkSoft;
  }

  /// True when running on Apple platforms (Cupertino style preferred).
  static bool get isApplePlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: accent,
      onPrimary: background,
      secondary: accentCyan,
      onSecondary: background,
      tertiary: accentBlue,
      onTertiary: ink,
      error: danger,
      onError: background,
      surface: surface,
      onSurface: ink,
      surfaceContainerHighest: surfaceMuted,
      outline: border,
      outlineVariant: divider,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
    );

    // Use Google Fonts on iOS/Android/Web, but system fonts on Linux
    // to avoid Skia rendering crashes.
    final textTheme = (!kIsWeb && Platform.isLinux)
        ? base.textTheme
        : GoogleFonts.manropeTextTheme(base.textTheme);

    return base.copyWith(
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: divider,
      splashColor: accent.withValues(alpha: 0.10),
      highlightColor: accent.withValues(alpha: 0.08),
      textTheme: textTheme.copyWith(
        displaySmall: const TextStyle(
          color: ink,
          fontSize: 34,
          fontWeight: FontWeight.w800,
          height: 1.08,
          letterSpacing: 0,
        ),
        headlineMedium: const TextStyle(
          color: ink,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          height: 1.12,
          letterSpacing: 0,
        ),
        titleLarge: const TextStyle(
          color: ink,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          height: 1.18,
          letterSpacing: 0,
        ),
        titleMedium: const TextStyle(
          color: ink,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          height: 1.24,
          letterSpacing: 0,
        ),
        titleSmall: const TextStyle(
          color: ink,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1.28,
          letterSpacing: 0,
        ),
        bodyLarge: const TextStyle(
          color: ink,
          fontSize: 16,
          height: 1.5,
          letterSpacing: 0,
        ),
        bodyMedium: const TextStyle(
          color: inkMuted,
          fontSize: 14,
          height: 1.46,
          letterSpacing: 0,
        ),
        bodySmall: const TextStyle(
          color: inkSoft,
          fontSize: 12,
          height: 1.42,
          letterSpacing: 0,
        ),
        labelLarge: const TextStyle(
          color: ink,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        labelMedium: const TextStyle(
          color: inkMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      iconTheme: const IconThemeData(color: inkMuted, size: 22),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: surfaceGlass,
        surfaceTintColor: Colors.transparent,
        elevation: elevationLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: const BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceMuted,
        selectedColor: accentSoft,
        disabledColor: surfaceMuted.withValues(alpha: 0.45),
        side: const BorderSide(color: border),
        labelStyle:
            const TextStyle(color: inkMuted, fontWeight: FontWeight.w700),
        secondaryLabelStyle:
            const TextStyle(color: ink, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceRaised.withValues(alpha: 0.72),
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
          borderSide: const BorderSide(color: accent, width: strokeStrong),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: const BorderSide(color: danger, width: strokeStrong),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: space4, vertical: space4),
        hintStyle: const TextStyle(color: inkSoft),
        labelStyle: const TextStyle(color: inkMuted),
        errorStyle: const TextStyle(color: danger),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: background,
          backgroundColor: accent,
          disabledForegroundColor: inkDisabled,
          disabledBackgroundColor: surfaceMuted,
          padding: const EdgeInsets.symmetric(
            horizontal: space5,
            vertical: space4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusS),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            letterSpacing: 0,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          disabledForegroundColor: inkDisabled,
          padding: const EdgeInsets.symmetric(
            horizontal: space5,
            vertical: space4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusS),
          ),
          side: const BorderSide(color: borderStrong),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: accent,
        textColor: ink,
        subtitleTextStyle: TextStyle(color: inkSoft),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentCyan;
          return inkSoft;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentSoft;
          return surfaceMuted;
        }),
        trackOutlineColor: WidgetStateProperty.all(border),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          if (states.contains(WidgetState.disabled)) return inkDisabled;
          return inkSoft;
        }),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: surfaceMuted,
        circularTrackColor: surfaceMuted,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceRaised,
        contentTextStyle: const TextStyle(color: ink),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusS),
          side: const BorderSide(color: border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: accentSoft,
        backgroundColor: surface.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? ink : inkSoft,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: 0,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: accent);
          }
          return const IconThemeData(color: inkSoft);
        }),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        indicatorColor: accentSoft,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedIconTheme: IconThemeData(color: accent),
        unselectedIconTheme: IconThemeData(color: inkSoft),
        selectedLabelTextStyle: TextStyle(
          color: ink,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: inkSoft,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: hairline,
        space: hairline,
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

class SecurePageBackground extends StatelessWidget {
  const SecurePageBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: AppUIv1.background, child: child);
  }
}

class SecureResponsiveFrame extends StatelessWidget {
  const SecureResponsiveFrame({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double? maxWidth;
  final EdgeInsets? padding;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Align(
          alignment: alignment,
          child: Padding(
            padding: padding ?? AppUIv1.pagePaddingFor(width),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth ?? AppUIv1.maxContentWidthFor(width),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class SecureSurface extends StatefulWidget {
  const SecureSurface({
    super.key,
    required this.child,
    this.variant = SecureSurfaceVariant.base,
    this.padding = const EdgeInsets.all(AppUIv1.space4),
    this.radius = AppUIv1.radiusCard,
    this.clipBehavior = Clip.antiAlias,
    this.onTap,
  });

  final Widget child;
  final SecureSurfaceVariant variant;
  final EdgeInsets padding;
  final double radius;
  final Clip clipBehavior;
  final VoidCallback? onTap;

  @override
  State<SecureSurface> createState() => _SecureSurfaceState();
}

class _SecureSurfaceState extends State<SecureSurface> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = _surfaceColors(widget.variant);
    final interactive = widget.onTap != null;
    final active = interactive && (_hovered || _pressed);
    final borderRadius = BorderRadius.circular(widget.radius);
    final decoration = BoxDecoration(
      color: colors.color,
      gradient: colors.gradient,
      borderRadius: borderRadius,
      border: Border.all(
        color: active
            ? Color.lerp(
                colors.border,
                AppUIv1.accentCyan,
                _pressed ? 0.42 : 0.28,
              )!
            : colors.border,
      ),
      boxShadow: colors.shadows,
    );

    Widget content = AnimatedContainer(
      duration: AppUIv1.durationFast,
      curve: AppUIv1.curveDefault,
      decoration: decoration,
      child: Padding(padding: widget.padding, child: widget.child),
    );

    content = ClipRRect(
      borderRadius: borderRadius,
      clipBehavior: widget.clipBehavior,
      child: content,
    );

    if (!interactive) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: widget.onTap,
        onHover: (value) => setState(() => _hovered = value),
        onHighlightChanged: (value) => setState(() => _pressed = value),
        splashColor: AppUIv1.accent.withValues(alpha: 0.08),
        highlightColor: AppUIv1.accentCyan.withValues(alpha: 0.06),
        child: content,
      ),
    );
  }

  _SurfaceColors _surfaceColors(SecureSurfaceVariant variant) {
    switch (variant) {
      case SecureSurfaceVariant.base:
        return _SurfaceColors(
          color: AppUIv1.surface,
          border: AppUIv1.border,
          shadows: AppUIv1.shadowSm,
        );
      case SecureSurfaceVariant.raised:
        return _SurfaceColors(
          color: AppUIv1.surfaceRaised,
          border: AppUIv1.borderStrong,
          shadows: AppUIv1.shadowMd,
        );
      case SecureSurfaceVariant.glass:
        return _SurfaceColors(
          color: AppUIv1.surfaceGlass,
          gradient: AppUIv1.surfaceGradient,
          border: AppUIv1.border,
          shadows: AppUIv1.shadowSm,
        );
      case SecureSurfaceVariant.accent:
        return _SurfaceColors(
          color: AppUIv1.accent,
          border: AppUIv1.accent,
          shadows: AppUIv1.shadowSm,
        );
      case SecureSurfaceVariant.success:
        return _SurfaceColors(
          color: AppUIv1.success.withValues(alpha: 0.10),
          border: AppUIv1.success.withValues(alpha: 0.38),
          shadows: AppUIv1.glowSuccess,
        );
      case SecureSurfaceVariant.warning:
        return _SurfaceColors(
          color: AppUIv1.warning.withValues(alpha: 0.10),
          border: AppUIv1.warning.withValues(alpha: 0.38),
          shadows: AppUIv1.shadowSm,
        );
      case SecureSurfaceVariant.danger:
        return _SurfaceColors(
          color: AppUIv1.danger.withValues(alpha: 0.10),
          border: AppUIv1.danger.withValues(alpha: 0.38),
          shadows: AppUIv1.glowDanger,
        );
    }
  }
}

class SecureStatePill extends StatelessWidget {
  const SecureStatePill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppUIv1.radiusFull),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppUIv1.space3,
          vertical: AppUIv1.space1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: color, size: 14),
              const SizedBox(width: AppUIv1.space1),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SurfaceColors {
  const _SurfaceColors({
    required this.color,
    required this.border,
    required this.shadows,
    this.gradient,
  });

  final Color color;
  final Color border;
  final List<BoxShadow> shadows;
  final Gradient? gradient;
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

import 'package:flutter/material.dart';

/// Black/blue tokens aligned with docs/WEBSITE_DESIGN_LOCK.md.
///
/// This file is the single source of truth for the application's visual
/// identity. Recolouring the whole app means editing [SwColors] here and
/// nothing else — widgets never hard-code colour values.
class SwColors {
  const SwColors._();

  static const background = Color(0xFF03060D);
  static const surface = Color(0xFF080F20);
  static const surfaceSecondary = Color(0xFF060C18);

  static const primary = Color(0xFF00B4FF);
  static const primaryStrong = Color(0xFF00B4FF);
  static const primarySoft = Color(0xFF0A2340);
  static const accent = Color(0xFF00B4FF);

  static const textPrimary = Color(0xFFD0E8FF);
  static const textSecondary = Color(0xFF8BA9C7);

  static const border = Color(0xFF1A3060);

  static const success = Color(0xFF00B4FF);
  static const warning = Color(0xFFF0BE64);
  static const error = Color(0xFFFF8F86);

  /// Neutral indicator used for the disconnected/idle state.
  static const idle = Color(0xFF8BA9C7);

  static const onPrimary = background;
  static const secondary = Color(0xFF0066CC);
  static const warningSoft = Color(0xFF292012);
  static const errorSoft = Color(0xFF301A20);
}

class SwSpacing {
  const SwSpacing._();

  static const xs = 8.0;
  static const sm = 16.0;
  static const md = 24.0;
  static const lg = 32.0;
  static const xl = 48.0;
}

class SwRadius {
  const SwRadius._();

  static const sm = 4.0;
  static const md = 6.0;
  static const lg = 8.0;
  static const pill = 999.0;
}

class SwLayout {
  const SwLayout._();

  /// Below this width the left navigation rail is replaced by a bottom bar.
  static const compactMax = 720.0;
  static const railWidth = 120.0;
  static const topBarHeight = 64.0;
  static const authPanelWidth = 460.0;
  static const contentMaxWidth = 560.0;
  static const connectWrap = 196.0;
  static const connectCircle = 184.0;
}

/// Restrained neutral shadows keep elevation legible without coloured glows.
class SwShadow {
  const SwShadow._();

  static List<BoxShadow> get card => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get connected => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.10),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get segment => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ];
}

class SwType {
  const SwType._();

  static const family = 'SpaceGrotesk';
  static const mono = 'JetBrainsMono';

  static const headline = TextStyle(
    fontFamily: family,
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.64,
    height: 1.18,
    color: SwColors.textPrimary,
  );

  static const title = TextStyle(
    fontFamily: family,
    fontSize: 21,
    fontWeight: FontWeight.w700,
    height: 1.25,
    color: SwColors.textPrimary,
  );

  static const body = TextStyle(
    fontFamily: family,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.6,
    color: SwColors.textSecondary,
  );

  static const label = TextStyle(
    fontFamily: mono,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.48,
    color: SwColors.textSecondary,
  );

  static const micro = TextStyle(
    fontFamily: mono,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.35,
    color: SwColors.textSecondary,
  );

  static const statValue = TextStyle(
    fontFamily: mono,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: SwColors.textPrimary,
  );

  static const connectLabel = TextStyle(
    fontFamily: mono,
    fontSize: 14,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.12,
    color: SwColors.textPrimary,
  );

  static const wordmark = TextStyle(
    fontFamily: family,
    fontSize: 17,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
    color: SwColors.textPrimary,
  );

  static const button = TextStyle(
    fontFamily: family,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
  );

  static const footnote = TextStyle(
    fontFamily: family,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.5,
    color: SwColors.textSecondary,
  );
}

class SwMotion {
  const SwMotion._();

  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 220);
  static const curve = Curves.easeOutCubic;
}

class SwTheme {
  const SwTheme._();

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: SwColors.primaryStrong,
      onPrimary: SwColors.onPrimary,
      secondary: SwColors.secondary,
      onSecondary: SwColors.textPrimary,
      surface: SwColors.surface,
      onSurface: SwColors.textPrimary,
      error: SwColors.error,
      onError: SwColors.onPrimary,
      outline: SwColors.border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: SwType.family,
      scaffoldBackgroundColor: SwColors.background,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        headlineLarge: SwType.headline,
        headlineMedium: SwType.headline,
        titleLarge: SwType.title,
        titleMedium: SwType.statValue,
        bodyLarge: SwType.body,
        bodyMedium: SwType.body,
        bodySmall: SwType.footnote,
        labelLarge: SwType.button,
        labelSmall: SwType.label,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SwColors.primaryStrong,
          foregroundColor: SwColors.onPrimary,
          disabledBackgroundColor: SwColors.surfaceSecondary,
          disabledForegroundColor: SwColors.textSecondary,
          minimumSize: const Size(0, 48),
          elevation: 0,
          textStyle: SwType.button,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SwRadius.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SwColors.textPrimary,
          minimumSize: const Size(0, 46),
          side: const BorderSide(color: SwColors.border),
          textStyle: SwType.button,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SwRadius.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SwColors.primaryStrong,
          textStyle: SwType.button,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SwColors.surface,
        hintStyle: SwType.body,
        labelStyle: SwType.body,
        floatingLabelStyle: SwType.body.copyWith(
          color: SwColors.primaryStrong,
          fontWeight: FontWeight.w700,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: _inputBorder(SwColors.border),
        enabledBorder: _inputBorder(SwColors.border),
        focusedBorder: _inputBorder(SwColors.primary, width: 1.6),
        errorBorder: _inputBorder(SwColors.error),
        focusedErrorBorder: _inputBorder(SwColors.error, width: 1.6),
        errorStyle: SwType.footnote.copyWith(color: SwColors.error),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: SwColors.primaryStrong,
        linearTrackColor: SwColors.surfaceSecondary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        elevation: 0,
        backgroundColor: SwColors.surface,
        indicatorColor: SwColors.primarySoft,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => SwType.micro.copyWith(
            fontSize: 11,
            letterSpacing: 0.4,
            color: states.contains(WidgetState.selected)
                ? SwColors.primaryStrong
                : SwColors.textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 20,
            color: states.contains(WidgetState.selected)
                ? SwColors.primaryStrong
                : SwColors.textSecondary,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: SwColors.border,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: SwColors.surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: SwColors.border,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(SwRadius.md),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

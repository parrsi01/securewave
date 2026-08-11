import 'package:flutter/material.dart';

/// SecureWave design tokens.
///
/// This file is the single source of truth for the application's visual
/// identity. Recolouring the whole app means editing [SwColors] here and
/// nothing else — widgets never hard-code colour values.
class SwColors {
  const SwColors._();

  static const background = Color(0xFFF6FAF7);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSecondary = Color(0xFFEEF5F0);

  static const primary = Color(0xFF9B8CF2);
  static const primaryStrong = Color(0xFF674FD9);
  static const primarySoft = Color(0xFFEDE9FD);
  static const accent = Color(0xFF9B8CF2);

  static const textPrimary = Color(0xFF171B19);
  static const textSecondary = Color(0xFF65707D);

  static const border = Color(0xFFE1E9E3);

  static const success = Color(0xFF674FD9);
  static const warning = Color(0xFFB8862B);
  static const error = Color(0xFFC0453B);

  /// Neutral indicator used for the disconnected/idle state.
  static const idle = Color(0xFF9AA4AF);

  static const onPrimary = Color(0xFFFFFFFF);
  static const warningSoft = Color(0xFFFBF3E2);
  static const errorSoft = Color(0xFFFBECEA);
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

  static const sm = 8.0;
  static const md = 10.0;
  static const lg = 12.0;
  static const pill = 999.0;
}

class SwLayout {
  const SwLayout._();

  /// Below this width the left navigation rail is replaced by a bottom bar.
  static const compactMax = 720.0;
  static const railWidth = 88.0;
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
          color: SwColors.textPrimary.withValues(alpha: 0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get connected => [
        BoxShadow(
          color: SwColors.textPrimary.withValues(alpha: 0.10),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get segment => [
        BoxShadow(
          color: SwColors.textPrimary.withValues(alpha: 0.08),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ];
}

class SwType {
  const SwType._();

  static const family = 'PlusJakartaSans';

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
    fontFamily: family,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.48,
    color: SwColors.textSecondary,
  );

  static const micro = TextStyle(
    fontFamily: family,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.35,
    color: SwColors.textSecondary,
  );

  static const statValue = TextStyle(
    fontFamily: family,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: SwColors.textPrimary,
  );

  static const connectLabel = TextStyle(
    fontFamily: family,
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

  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: SwColors.primaryStrong,
      onPrimary: SwColors.onPrimary,
      secondary: SwColors.primary,
      onSecondary: SwColors.onPrimary,
      surface: SwColors.surface,
      onSurface: SwColors.textPrimary,
      error: SwColors.error,
      onError: SwColors.onPrimary,
      outline: SwColors.border,
    );

    return ThemeData(
      useMaterial3: true,
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

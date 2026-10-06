import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const backgroundPrimary = Color(0xFF03060D);
  static const backgroundSecondary = Color(0xFF060C18);
  static const surfacePrimary = Color(0xFF080F20);
  static const surfaceElevated = Color(0xFF0C172B);
  static const surfaceInteractive = Color(0xFF10213A);
  static const borderSubtle = Color(0xFF0F1E3A);
  static const borderStrong = Color(0xFF617E9E);
  static const textPrimary = Color(0xFFD0E8FF);
  static const textSecondary = Color(0xFF8BA9C7);
  static const textMuted = Color(0xFF7896B5);
  static const accentPrimary = Color(0xFF00B4FF);
  static const accentHover = Color(0xFF33C3FF);
  static const accentPressed = Color(0xFF009FE3);
  static const onAccent = backgroundPrimary;
  static const connected = Color(0xFF00E5A0);
  static const disconnected = textSecondary;
  static const warning = Color(0xFFFFD166);
  static const error = Color(0xFFFF8F86);
  static const focusRing = accentPrimary;
  static const disabledForeground = textMuted;
  static const disabledBackground = surfaceInteractive;

  static const interactionDuration = Duration(milliseconds: 120);
  static const stateDuration = Duration(milliseconds: 160);
  static const ringDuration = Duration(milliseconds: 1200);
  static const curve = Curves.easeOut;

  static Color stateSurface(Color hue, {double alpha = .08}) =>
      Color.alphaBlend(hue.withValues(alpha: alpha), surfacePrimary);

  static bool reduceMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  static double outerPadding(double width) => width < 640
      ? 16
      : width < 1024
          ? 24
          : 32;

  static TextStyle type(double size, double weight, double height,
          {Color color = textPrimary,
          double spacing = 0,
          String family = 'SpaceGrotesk'}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: FontWeight.values[(weight / 100).round() - 1],
        fontVariations: [FontVariation('wght', weight)],
        height: height,
        letterSpacing: spacing,
        color: color,
      );

  static TextStyle get wordmark => type(20, 600, 1.25);
  static TextStyle get pageTitle => type(28, 600, 1.25, spacing: -.3);
  static TextStyle get sectionTitle => type(18, 600, 1.35);
  static TextStyle get body => type(16, 400, 1.5);
  static TextStyle get smallBody => type(14, 400, 1.5, color: textSecondary);
  static TextStyle get fieldLabel => type(14, 500, 1.4);
  static TextStyle get button => type(16, 600, 1.25);
  static TextStyle get caption => type(13, 400, 1.45, color: textSecondary);
  static TextStyle get transfer => type(28, 400, 1.3, family: 'JetBrainsMono');

  static final ThemeData dark = _buildDark();

  static ThemeData _buildDark() {
    final ordinaryButton = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(44, 52)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 16)),
      shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
      textStyle: WidgetStatePropertyAll(button),
      animationDuration: interactionDuration,
      elevation: const WidgetStatePropertyAll(0),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      side: WidgetStateProperty.resolveWith((states) => BorderSide(
          width: 2,
          color: states.contains(WidgetState.focused)
              ? focusRing
              : Colors.transparent)),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'SpaceGrotesk',
      scaffoldBackgroundColor: backgroundPrimary,
      colorScheme: const ColorScheme.dark(
        primary: accentPrimary,
        onPrimary: onAccent,
        surface: surfacePrimary,
        onSurface: textPrimary,
        onSurfaceVariant: textSecondary,
        outline: borderStrong,
        error: error,
        onError: backgroundPrimary,
      ),
      textTheme: TextTheme(
        headlineSmall: type(40, 600, 1.2, spacing: -.6),
        titleLarge: pageTitle,
        titleMedium: sectionTitle,
        bodyLarge: body,
        bodyMedium: smallBody,
        labelLarge: fieldLabel,
        labelMedium: caption,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ordinaryButton.copyWith(
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? disabledForeground
                  : onAccent),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return disabledBackground;
            }
            if (states.contains(WidgetState.pressed)) return accentPressed;
            if (states.contains(WidgetState.hovered)) {
              return accentHover;
            }
            return accentPrimary;
          }),
          side: const WidgetStatePropertyAll(
              BorderSide(color: Colors.transparent)),
          backgroundBuilder: (context, states, child) => Stack(
            fit: StackFit.passthrough,
            clipBehavior: Clip.none,
            children: [
              if (child != null) child,
              if (states.contains(WidgetState.focused))
                Positioned.fill(
                  left: -4,
                  right: -4,
                  top: -4,
                  bottom: -4,
                  child: IgnorePointer(
                      child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: focusRing, width: 2),
                    ),
                  )),
                ),
            ],
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ordinaryButton.copyWith(
          foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.disabled)
                  ? disabledForeground
                  : states.contains(WidgetState.hovered)
                      ? textPrimary
                      : textSecondary),
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.pressed)
                  ? surfaceInteractive
                  : Colors.transparent),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfacePrimary,
        hoverColor: surfaceElevated,
        constraints: const BoxConstraints(minHeight: 52),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: smallBody.copyWith(color: textMuted),
        errorStyle: caption.copyWith(color: error),
        errorMaxLines: 4,
        enabledBorder: _fieldBorder(borderStrong),
        focusedBorder: _fieldBorder(focusRing, width: 2),
        errorBorder: _fieldBorder(error),
        focusedErrorBorder: _fieldBorder(error, width: 2),
      ),
      dividerTheme:
          const DividerThemeData(color: borderSubtle, thickness: 1, space: 1),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: color, width: width));
}

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

class AppUIv1 {
  static const Color background = Color(0xFF07111F);
  static const Color backgroundStrong = Color(0xFF0E1B2E);
  static const Color surface = Color(0xFF111D31);
  static const Color surfaceMuted = Color(0xFF16253D);
  static const Color accent = Color(0xFF00BFA5);
  static const Color accentStrong = Color(0xFF00E5C4);
  static const Color accentSoft = Color(0x3320E3C4);
  static const Color accentSun = Color(0xFFF4C95D);
  static const Color success = Color(0xFF2BD67B);
  static const Color warning = Color(0xFFFF8C5A);
  static const Color danger = Color(0xFFFF5D7A);
  static const Color ink = Color(0xFFF6F9FC);
  static const Color inkMuted = Color(0xFFB4C0D2);
  static const Color inkSoft = Color(0xFF7D90AB);
  static const Color border = Color(0xFF20314C);

  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;
  static const double space6 = 32;
  static const double space7 = 48;

  static ThemeData theme() {
    final base = FlexThemeData.dark(
      scheme: FlexScheme.deepBlue,
      surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
      blendLevel: 18,
      appBarElevation: 0,
      scaffoldBackground: background,
      colors: const FlexSchemeColor(
        primary: accent,
        primaryContainer: surfaceMuted,
        secondary: accentSun,
        secondaryContainer: Color(0xFF553F0D),
        tertiary: success,
        tertiaryContainer: Color(0xFF0F4731),
        appBarColor: background,
        error: danger,
      ),
      subThemesData: const FlexSubThemesData(
        interactionEffects: true,
        blendOnLevel: 16,
        useMaterial3Typography: true,
        inputDecoratorIsFilled: true,
        inputDecoratorBorderType: FlexInputBorderType.outline,
        inputDecoratorRadius: 18,
        defaultRadius: 22,
        elevatedButtonRadius: 999,
        outlinedButtonRadius: 999,
        filledButtonRadius: 999,
        cardRadius: 28,
        navigationBarIndicatorRadius: 18,
      ),
      textTheme: Typography.whiteMountainView,
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      dividerColor: border,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: ink,
      ),
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          color: ink,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          color: ink,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: ink,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: ink,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(color: ink),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(color: inkMuted),
        bodySmall: base.textTheme.bodySmall?.copyWith(color: inkSoft),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: surfaceMuted,
        hintStyle: const TextStyle(color: inkSoft),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: backgroundStrong,
        indicatorColor: accentSoft,
        labelTextStyle: WidgetStateProperty.all(
          base.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static String formatBytes(double bytesPerSecond) {
    if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    if (bytesPerSecond >= 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${bytesPerSecond.toStringAsFixed(0)} B/s';
  }

  static String formatDataAmount(int bytes) {
    final kb = bytes / 1024;
    final mb = kb / 1024;
    final gb = mb / 1024;
    if (gb >= 1) {
      return '${gb.toStringAsFixed(2)} GB';
    }
    if (mb >= 1) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    if (kb >= 1) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  static String formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}

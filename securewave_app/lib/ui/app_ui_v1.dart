import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppUIv1 {
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

  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;
  static const double space6 = 32;
  static const double space7 = 48;

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

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: GoogleFonts.manropeTextTheme(base.textTheme).copyWith(
        headlineMedium: const TextStyle(fontWeight: FontWeight.w700, color: ink),
        titleLarge: const TextStyle(fontWeight: FontWeight.w700, color: ink),
        titleMedium: const TextStyle(fontWeight: FontWeight.w600, color: ink),
        bodyLarge: const TextStyle(color: ink),
        bodyMedium: const TextStyle(color: inkMuted),
        bodySmall: const TextStyle(color: inkSoft),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
        foregroundColor: ink,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: accent),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: inkSoft),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          side: const BorderSide(color: border),
        ),
      ),
      dividerColor: border,
      listTileTheme: const ListTileThemeData(
        iconColor: accent,
        textColor: ink,
      ),
    );
  }
}

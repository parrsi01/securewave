import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Colors - SecureWave v4 Ocean Palette
  static const Color primary = Color(0xFF0EA5E9);
  static const Color secondary = Color(0xFF14B8A6);
  static const Color accent = Color(0xFFF59E0B);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF38BDF8);

  // Gradient for buttons and highlights
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, secondary, accent],
    stops: [0.0, 0.6, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient buttonGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Dark background colors
  static const Color bgDark = Color(0xFF0B1120);
  static const Color bgCard = Color(0xFF0F172A);
  static const Color bgSecondary = Color(0xFF132036);
  static const Color borderDark = Color(0xFF1E2A40);

  // Light background colors
  static const Color bgLight = Color(0xFFF7FAFC);
  static const Color bgLightCard = Color(0xFFFFFFFF);
  static const Color bgLightSecondary = Color(0xFFEDF5F7);
  static const Color borderLight = Color(0xFFD0E4EC);

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: primary,
          secondary: secondary,
          tertiary: accent,
          error: error,
        ),
        scaffoldBackgroundColor: bgDark,
        cardColor: bgCard,
        cardTheme: CardThemeData(
          color: bgCard,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: EdgeInsets.zero,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(
          backgroundColor: bgDark,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: bgDark,
          selectedItemColor: primary,
          unselectedItemColor: Color(0xFF94A3B8),
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: bgDark,
          selectedIconTheme: IconThemeData(color: primary),
          selectedLabelTextStyle: TextStyle(color: primary, fontWeight: FontWeight.w600),
          unselectedIconTheme: IconThemeData(color: Color(0xFF94A3B8)),
          unselectedLabelTextStyle: TextStyle(color: Color(0xFF94A3B8)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        textTheme: GoogleFonts.manropeTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ).copyWith(
          headlineLarge: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.6),
          headlineMedium: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4),
          titleLarge: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          bodyLarge: const TextStyle(fontSize: 16, height: 1.5),
          bodyMedium: const TextStyle(fontSize: 14, height: 1.5),
          bodySmall: const TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF94A3B8)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: bgSecondary,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderDark),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderDark),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primary),
          ),
        ),
      );

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: primary,
          secondary: secondary,
          tertiary: accent,
          error: error,
        ),
        scaffoldBackgroundColor: bgLight,
        cardColor: bgLightCard,
        cardTheme: CardThemeData(
          color: bgLightCard,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: EdgeInsets.zero,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(
          backgroundColor: bgLight,
          elevation: 0,
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: primary,
          unselectedItemColor: Color(0xFF64748B),
        ),
        navigationRailTheme: const NavigationRailThemeData(
          selectedIconTheme: IconThemeData(color: primary),
          selectedLabelTextStyle: TextStyle(color: primary, fontWeight: FontWeight.w600),
          unselectedIconTheme: IconThemeData(color: Color(0xFF64748B)),
          unselectedLabelTextStyle: TextStyle(color: Color(0xFF64748B)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: bgLightSecondary,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderLight),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primary),
          ),
        ),
        textTheme: GoogleFonts.manropeTextTheme(
          ThemeData(brightness: Brightness.light).textTheme,
        ).copyWith(
          headlineLarge: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.6),
          headlineMedium: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4),
          titleLarge: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          bodyLarge: const TextStyle(fontSize: 16, height: 1.5),
          bodyMedium: const TextStyle(fontSize: 14, height: 1.5),
          bodySmall: const TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF64748B)),
        ),
      );
}

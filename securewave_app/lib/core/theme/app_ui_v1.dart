/// SecureWave VPN - UI v1.0 Theme
/// Created: 2026-01-25
/// Palette: Calm Slate (Professional, Trustworthy, Beginner-Friendly)

import 'package:flutter/material.dart';

class AppUIv1 {
  // PRIMARY PALETTE - Slate Blue (Calm + Trust)
  static const Color primary = Color(0xFF475569);        // Slate-600
  static const Color primaryLight = Color(0xFF64748b);   // Slate-500
  static const Color primaryDark = Color(0xFF334155);    // Slate-700

  // ACCENT - Soft Blue (Action without aggression)
  static const Color accent = Color(0xFF3b82f6);         // Blue-500
  static const Color accentLight = Color(0xFF60a5fa);    // Blue-400
  static const Color accentDark = Color(0xFF2563eb);     // Blue-600

  // BACKGROUNDS
  static const Color bgPage = Color(0xFFF8FAFC);         // Slate-50
  static const Color bgCard = Color(0xFFFFFFFF);         // White
  static const Color bgCardHover = Color(0xFFF1F5F9);    // Slate-100

  // TEXT
  static const Color textPrimary = Color(0xFF0F172A);    // Slate-900
  static const Color textSecondary = Color(0xFF475569);  // Slate-600
  static const Color textTertiary = Color(0xFF64748b);   // Slate-500
  static const Color textMuted = Color(0xFF94A3B8);      // Slate-400

  // BORDERS
  static const Color borderLight = Color(0xFFE2E8F0);    // Slate-200
  static const Color borderMedium = Color(0xFFCBD5E1);   // Slate-300
  static const Color borderDark = Color(0xFF94A3B8);     // Slate-400

  // SEMANTIC COLORS
  static const Color success = Color(0xFF10B981);        // Green-500
  static const Color successBg = Color(0xFFD1FAE5);      // Green-100
  static const Color error = Color(0xFFEF4444);          // Red-500
  static const Color errorBg = Color(0xFFFEE2E2);        // Red-100
  static const Color warning = Color(0xFFF59E0B);        // Amber-500
  static const Color warningBg = Color(0xFFFEF3C7);      // Amber-100
  static const Color info = Color(0xFF3b82f6);           // Blue-500
  static const Color infoBg = Color(0xFFDBEAFE);         // Blue-100

  // SPACING (4px base)
  static const double space1 = 4.0;
  static const double space2 = 8.0;
  static const double space3 = 12.0;
  static const double space4 = 16.0;
  static const double space5 = 20.0;
  static const double space6 = 24.0;
  static const double space8 = 32.0;
  static const double space10 = 40.0;
  static const double space12 = 48.0;
  static const double space16 = 64.0;
  static const double space20 = 80.0;

  // BORDER RADIUS
  static const double radiusSm = 6.0;
  static const double radiusMd = 8.0;
  static const double radiusLg = 12.0;
  static const double radiusXl = 16.0;
  static const double radius2xl = 20.0;
  static const double radiusFull = 9999.0;

  // BUTTON SIZES (Large for touch)
  static const double btnHeightSm = 44.0;
  static const double btnHeight = 52.0;
  static const double btnHeightLg = 60.0;

  // Get Light Theme
  static ThemeData getLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // Color Scheme
      colorScheme: const ColorScheme.light(
        primary: accent,
        onPrimary: Colors.white,
        secondary: primary,
        onSecondary: Colors.white,
        surface: bgCard,
        onSurface: textPrimary,
        error: error,
        onError: Colors.white,
      ),

      // Scaffold
      scaffoldBackgroundColor: bgPage,

      // App Bar
      appBarTheme: const AppBarTheme(
        backgroundColor: bgCard,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
      ),

      // Elevated Button (Primary Button)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(btnHeight),
          padding: const EdgeInsets.symmetric(horizontal: space8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Outlined Button (Secondary Button)
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size.fromHeight(btnHeight),
          padding: const EdgeInsets.symmetric(horizontal: space8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
          side: const BorderSide(
            color: borderMedium,
            width: 2,
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Text Button (Ghost Button)
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: textSecondary,
          minimumSize: const Size.fromHeight(btnHeight),
          padding: const EdgeInsets.symmetric(horizontal: space8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Card
      cardTheme: CardTheme(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: const BorderSide(
            color: borderLight,
            width: 1,
          ),
        ),
        margin: const EdgeInsets.all(0),
      ),

      // Input Decoration (Forms)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgCard,
        contentPadding: const EdgeInsets.all(space4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(
            color: borderLight,
            width: 2,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(
            color: borderLight,
            width: 2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(
            color: accent,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(
            color: error,
            width: 2,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(
            color: error,
            width: 2,
          ),
        ),
        labelStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: textSecondary,
        ),
        hintStyle: const TextStyle(
          color: textMuted,
        ),
        errorStyle: const TextStyle(
          color: error,
          fontSize: 15,
        ),
      ),

      // Text Theme
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          height: 1.2,
        ),
        displayMedium: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          height: 1.2,
        ),
        displaySmall: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          height: 1.2,
        ),
        headlineLarge: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          height: 1.2,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          height: 1.2,
        ),
        headlineSmall: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          height: 1.2,
        ),
        bodyLarge: TextStyle(
          fontSize: 17,  // Larger base font
          fontWeight: FontWeight.w400,
          color: textSecondary,
          height: 1.6,
        ),
        bodyMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: textSecondary,
          height: 1.6,
        ),
        bodySmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: textTertiary,
          height: 1.6,
        ),
        labelLarge: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        labelMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: textSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textTertiary,
        ),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: borderLight,
        thickness: 1,
        space: 1,
      ),

      // Icon Theme
      iconTheme: const IconThemeData(
        color: textSecondary,
        size: 24,
      ),
    );
  }

  // Get Dark Theme
  static ThemeData getDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      // Color Scheme
      colorScheme: const ColorScheme.dark(
        primary: accentLight,
        onPrimary: Color(0xFF0F172A),
        secondary: Color(0xFF64748b),
        onSecondary: Colors.white,
        surface: Color(0xFF1E293B),  // Slate-800
        onSurface: Color(0xFFF1F5F9),  // Slate-100
        error: error,
        onError: Colors.white,
      ),

      // Scaffold
      scaffoldBackgroundColor: const Color(0xFF0F172A),  // Slate-900

      // App Bar
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E293B),  // Slate-800
        foregroundColor: Color(0xFFF1F5F9),  // Slate-100
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Color(0xFFF1F5F9),
        ),
      ),

      // Elevated Button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentLight,
          foregroundColor: const Color(0xFF0F172A),
          minimumSize: const Size.fromHeight(btnHeight),
          padding: const EdgeInsets.symmetric(horizontal: space8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Card
      cardTheme: CardTheme(
        color: const Color(0xFF1E293B),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: const BorderSide(
            color: Color(0xFF334155),  // Slate-700
            width: 1,
          ),
        ),
        margin: const EdgeInsets.all(0),
      ),

      // Text Theme (inherits from light theme with color adjustments)
      textTheme: getLightTheme().textTheme.apply(
        displayColor: const Color(0xFFF1F5F9),
        bodyColor: const Color(0xFFCBD5E1),
      ),
    );
  }
}

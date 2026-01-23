import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// SecureWave VPN - v5.0 Design System
/// PrivadoVPN-Inspired Dark Theme with Orange/Green Accents
class AppTheme {
  // Brand Colors - Dark Theme Primary
  static const Color bgDarkest = Color(0xFF080A0B);
  static const Color bgDark = Color(0xFF1C1E22);
  static const Color bgCard = Color(0xFF25272D);
  static const Color bgCardHover = Color(0xFF30343B);
  static const Color bgElevated = Color(0xFF2D3038);

  // Accent Colors
  static const Color accentOrange = Color(0xFFFF8F00);
  static const Color accentOrangeDark = Color(0xFFF86605);
  static const Color accentGreen = Color(0xFF28D799);
  static const Color accentGreenDark = Color(0xFF1FA87A);
  static const Color accentPurple = Color(0xFF5058C8);

  // Semantic Colors
  static const Color success = Color(0xFF28D799);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Text Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFC1C5CD);
  static const Color textTertiary = Color(0xFF93999C);
  static const Color textMuted = Color(0xFF6B7280);

  // Border Colors
  static const Color borderPrimary = Color(0x14FFFFFF);
  static const Color borderSecondary = Color(0x1FFFFFFF);

  // Light Theme Colors
  static const Color bgLightest = Color(0xFFF8FAFC);
  static const Color bgLight = Color(0xFFFFFFFF);
  static const Color bgLightCard = Color(0xFFFFFFFF);
  static const Color bgLightSecondary = Color(0xFFF1F5F9);
  static const Color borderLight = Color(0x14000000);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [accentOrange, accentOrangeDark],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [accentGreen, accentGreenDark],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [bgCardHover, bgDark],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Dark Theme (Default)
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: accentOrange,
          secondary: accentGreen,
          tertiary: accentPurple,
          error: error,
          surface: bgCard,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: textPrimary,
        ),
        scaffoldBackgroundColor: bgDarkest,
        cardColor: bgCard,
        cardTheme: CardThemeData(
          color: bgCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: borderPrimary),
          ),
          margin: EdgeInsets.zero,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(
          backgroundColor: bgDark,
          foregroundColor: textPrimary,
          elevation: 0,
          centerTitle: false,
        ),
        dividerTheme: const DividerThemeData(
          color: borderPrimary,
          thickness: 1,
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          tileColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: bgDark,
          selectedItemColor: accentOrange,
          unselectedItemColor: textTertiary,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: bgDark,
          selectedIconTheme: IconThemeData(color: accentOrange),
          selectedLabelTextStyle:
              TextStyle(color: accentOrange, fontWeight: FontWeight.w600),
          unselectedIconTheme: IconThemeData(color: textTertiary),
          unselectedLabelTextStyle: TextStyle(color: textTertiary),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: accentOrange,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentOrange,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: accentOrange,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            side: const BorderSide(color: accentOrange, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: accentOrange,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: bgCard,
          labelStyle: const TextStyle(color: textSecondary),
          side: const BorderSide(color: borderPrimary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ).copyWith(
          displayLarge: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
            color: textPrimary,
          ),
          displayMedium: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            color: textPrimary,
          ),
          headlineLarge: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: textPrimary,
          ),
          headlineMedium: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: textPrimary,
          ),
          titleLarge: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
          bodyLarge: const TextStyle(
            fontSize: 16,
            height: 1.5,
            color: textSecondary,
          ),
          bodyMedium: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: textSecondary,
          ),
          bodySmall: const TextStyle(
            fontSize: 12,
            height: 1.5,
            color: textTertiary,
          ),
          labelLarge: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: bgCard,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderPrimary),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderPrimary),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: accentOrange, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: error),
          ),
          hintStyle: const TextStyle(color: textMuted),
          labelStyle: const TextStyle(color: textSecondary),
        ),
        dialogTheme: DialogTheme(
          backgroundColor: bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: bgCard,
          contentTextStyle: const TextStyle(color: textPrimary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: accentOrange,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return textTertiary;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return accentGreen;
            }
            return bgElevated;
          }),
        ),
      );

  /// Light Theme
  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: accentOrange,
          secondary: accentGreen,
          tertiary: accentPurple,
          error: error,
          surface: bgLightCard,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
        ),
        scaffoldBackgroundColor: bgLightest,
        cardColor: bgLightCard,
        cardTheme: CardThemeData(
          color: bgLightCard,
          elevation: 1,
          shadowColor: Colors.black.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: borderLight),
          ),
          margin: EdgeInsets.zero,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(
          backgroundColor: bgLight,
          elevation: 0,
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: bgLight,
          selectedItemColor: accentOrange,
          unselectedItemColor: Color(0xFF64748B),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: bgLight,
          selectedIconTheme: IconThemeData(color: accentOrange),
          selectedLabelTextStyle:
              TextStyle(color: accentOrange, fontWeight: FontWeight.w600),
          unselectedIconTheme: IconThemeData(color: Color(0xFF64748B)),
          unselectedLabelTextStyle: TextStyle(color: Color(0xFF64748B)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentOrange,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: bgLightSecondary,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
            borderSide: const BorderSide(color: accentOrange, width: 2),
          ),
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData(brightness: Brightness.light).textTheme,
        ).copyWith(
          displayLarge: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
            color: Color(0xFF0F172A),
          ),
          displayMedium: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            color: Color(0xFF0F172A),
          ),
          headlineLarge: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: Color(0xFF0F172A),
          ),
          headlineMedium: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: Color(0xFF0F172A),
          ),
          titleLarge: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
          bodyLarge: const TextStyle(
            fontSize: 16,
            height: 1.5,
            color: Color(0xFF334155),
          ),
          bodyMedium: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Color(0xFF334155),
          ),
          bodySmall: const TextStyle(
            fontSize: 12,
            height: 1.5,
            color: Color(0xFF64748B),
          ),
        ),
      );
}

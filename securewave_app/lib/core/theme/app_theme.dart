import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// SecureWave VPN - v5.1 Design System
/// Lavender Light Theme - Modern Consumer VPN Aesthetic
/// Brand Palette: #F5EFFF, #E5D9F2, #CDC1FF, #A294F9
class AppTheme {
  // Brand Colors - Lavender Light Theme
  static const Color bgLightest = Color(0xFFF5EFFF);
  static const Color bgLight = Color(0xFFF5EFFF);
  static const Color bgCard = Color(0xFFE5D9F2);
  static const Color bgCardHover = Color(0xFFDDD0ED);
  static const Color bgElevated = Color(0xFFFFFFFF);

  // Primary Accent - Purple
  static const Color primaryColor = Color(0xFFA294F9);
  static const Color primaryDark = Color(0xFF8B7CF7);
  static const Color primaryLight = Color(0xFFB8ADF9);

  // Secondary Accent
  static const Color secondaryColor = Color(0xFFCDC1FF);
  static const Color secondaryDark = Color(0xFFB8A9F5);

  // Legacy aliases (for backward compatibility)
  static const Color primary = primaryColor;
  static const Color secondary = secondaryColor;
  static const Color accent = primaryColor;
  static const Color accentOrange = primaryColor;
  static const Color accentOrangeDark = primaryDark;
  static const Color accentGreen = Color(0xFF10B981);
  static const Color accentGreenDark = Color(0xFF059669);
  static const Color accentPurple = primaryColor;

  // Semantic Colors
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Text Colors - Light Theme (Default)
  static const Color textPrimary = Color(0xFF1F1F1F);
  static const Color textSecondary = Color(0xFF4A4A4A);
  static const Color textTertiary = Color(0xFF6B6B6B);
  static const Color textMuted = Color(0xFF9CA3AF);

  // Border Colors
  static const Color borderPrimary = Color(0x33A294F9);
  static const Color borderSecondary = Color(0x59A294F9);
  static const Color borderLight = Color(0x33A294F9);
  static const Color borderDark = Color(0x33FFFFFF);

  // Dark Theme Colors
  static const Color bgDarkest = Color(0xFF1A1625);
  static const Color bgDark = Color(0xFF241D30);
  static const Color bgDarkCard = Color(0xFF2D2540);
  static const Color bgDarkElevated = Color(0xFF322A45);
  static const Color textDarkPrimary = Color(0xFFFFFFFF);
  static const Color textDarkSecondary = Color(0xFFD4D0DE);

  // Light Theme Colors (for compatibility)
  static const Color bgLightCard = Color(0xFFE5D9F2);
  static const Color bgLightSecondary = Color(0xFFE5D9F2);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryColor, secondaryColor],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [accentGreen, accentGreenDark],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [bgElevated, bgLightest],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Alias for backward compatibility
  static const LinearGradient buttonGradient = primaryGradient;

  /// Light Theme (Default)
  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: primaryColor,
          secondary: secondaryColor,
          tertiary: accentGreen,
          error: error,
          surface: bgCard,
          onPrimary: Colors.white,
          onSecondary: textPrimary,
          onSurface: textPrimary,
        ),
        scaffoldBackgroundColor: bgLightest,
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
          backgroundColor: bgLightest,
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
          backgroundColor: bgElevated,
          selectedItemColor: primaryColor,
          unselectedItemColor: textTertiary,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: bgElevated,
          selectedIconTheme: IconThemeData(color: primaryColor),
          selectedLabelTextStyle:
              TextStyle(color: primaryColor, fontWeight: FontWeight.w600),
          unselectedIconTheme: IconThemeData(color: textTertiary),
          unselectedLabelTextStyle: TextStyle(color: textTertiary),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
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
            foregroundColor: primaryColor,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            side: const BorderSide(color: primaryColor, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
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
          ThemeData(brightness: Brightness.light).textTheme,
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
          fillColor: bgElevated,
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
            borderSide: const BorderSide(color: primaryColor, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: error),
          ),
          hintStyle: const TextStyle(color: textMuted),
          labelStyle: const TextStyle(color: textSecondary),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: bgElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: bgDarkCard,
          contentTextStyle: const TextStyle(color: textDarkPrimary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: primaryColor,
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
            return bgCard;
          }),
        ),
      );

  /// Dark Theme
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: primaryColor,
          secondary: secondaryColor,
          tertiary: accentGreen,
          error: error,
          surface: bgDarkCard,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: textDarkPrimary,
        ),
        scaffoldBackgroundColor: bgDarkest,
        cardColor: bgDarkCard,
        cardTheme: CardThemeData(
          color: bgDarkCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: secondaryColor.withValues(alpha: 0.15)),
          ),
          margin: EdgeInsets.zero,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(
          backgroundColor: bgDark,
          foregroundColor: textDarkPrimary,
          elevation: 0,
          centerTitle: false,
        ),
        dividerTheme: DividerThemeData(
          color: secondaryColor.withValues(alpha: 0.15),
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
          selectedItemColor: primaryColor,
          unselectedItemColor: textDarkSecondary,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: bgDark,
          selectedIconTheme: IconThemeData(color: primaryColor),
          selectedLabelTextStyle:
              TextStyle(color: primaryColor, fontWeight: FontWeight.w600),
          unselectedIconTheme: IconThemeData(color: textDarkSecondary),
          unselectedLabelTextStyle: TextStyle(color: textDarkSecondary),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
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
            foregroundColor: primaryColor,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            side: const BorderSide(color: primaryColor, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: bgDarkCard,
          labelStyle: const TextStyle(color: textDarkSecondary),
          side: BorderSide(color: secondaryColor.withValues(alpha: 0.25)),
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
            color: textDarkPrimary,
          ),
          displayMedium: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            color: textDarkPrimary,
          ),
          headlineLarge: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: textDarkPrimary,
          ),
          headlineMedium: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: textDarkPrimary,
          ),
          titleLarge: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: textDarkPrimary,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textDarkPrimary,
          ),
          bodyLarge: const TextStyle(
            fontSize: 16,
            height: 1.5,
            color: textDarkSecondary,
          ),
          bodyMedium: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: textDarkSecondary,
          ),
          bodySmall: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: textDarkSecondary.withValues(alpha: 0.7),
          ),
          labelLarge: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textDarkPrimary,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: bgDarkCard,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: secondaryColor.withValues(alpha: 0.15)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: secondaryColor.withValues(alpha: 0.15)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primaryColor, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: error),
          ),
          hintStyle: TextStyle(color: textDarkSecondary.withValues(alpha: 0.5)),
          labelStyle: const TextStyle(color: textDarkSecondary),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: bgDarkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: bgDarkElevated,
          contentTextStyle: const TextStyle(color: textDarkPrimary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: primaryColor,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return textDarkSecondary;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return accentGreen;
            }
            return bgDarkElevated;
          }),
        ),
      );
}

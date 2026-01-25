import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// SecureWave VPN - v1.0 Design System
/// True v1.0 - Clean, Calm, Beginner-Friendly
/// Brand Palette: Teal (#0D9488 to #14B8A6)
/// Philosophy: Calm, trustworthy, minimal, approachable
class AppTheme {
  // Brand Colors - Light Theme (Default)
  static const Color bgPage = Color(0xFFF8FAFC);
  static const Color bgCard = Color(0xFFFFFFFF);
  static const Color bgCardHover = Color(0xFFF1F5F9);
  static const Color bgElevated = Color(0xFFFFFFFF);

  // Primary - Teal (Calm, Trustworthy)
  static const Color primaryColor = Color(0xFF0D9488);
  static const Color primaryDark = Color(0xFF0F766E);
  static const Color primaryLight = Color(0xFF14B8A6);

  // Secondary - Slate
  static const Color secondaryColor = Color(0xFF64748B);
  static const Color secondaryDark = Color(0xFF475569);
  static const Color secondaryLight = Color(0xFF94A3B8);

  // Accent - Warm Amber (for highlights)
  static const Color accentColor = Color(0xFFF59E0B);
  static const Color accentDark = Color(0xFFD97706);
  static const Color accentLight = Color(0xFFFBBF24);

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
  static const Color info = Color(0xFF0D9488);

  // Text Colors - Light Theme (Default)
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textTertiary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Border Colors
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color borderMedium = Color(0xFFCBD5E1);
  static const Color borderFocus = Color(0xFF0D9488);

  // Legacy border aliases
  static const Color borderPrimary = borderLight;
  static const Color borderSecondary = borderMedium;
  static const Color borderDark = Color(0xFF334155);

  // Dark Theme Colors
  static const Color bgDarkest = Color(0xFF0F172A);
  static const Color bgDark = Color(0xFF1E293B);
  static const Color bgDarkCard = Color(0xFF1E293B);
  static const Color bgDarkElevated = Color(0xFF334155);
  static const Color textDarkPrimary = Color(0xFFF1F5F9);
  static const Color textDarkSecondary = Color(0xFFCBD5E1);
  static const Color textDarkTertiary = Color(0xFF94A3B8);

  // Light Theme Colors (for compatibility)
  static const Color bgLightest = bgPage;
  static const Color bgLight = bgPage;
  static const Color bgLightCard = bgCard;
  static const Color bgLightSecondary = bgCardHover;

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryColor, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [accentGreen, accentGreenDark],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [bgElevated, bgPage],
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
        scaffoldBackgroundColor: bgPage,
        cardColor: bgCard,
        cardTheme: CardThemeData(
          color: bgCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: borderLight),
          ),
          margin: EdgeInsets.zero,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(
          backgroundColor: bgCard,
          foregroundColor: textPrimary,
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
        ),
        dividerTheme: const DividerThemeData(
          color: borderLight,
          thickness: 1,
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 17,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryColor,
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            side: const BorderSide(color: primaryColor, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
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
          backgroundColor: bgCardHover,
          labelStyle: const TextStyle(color: textSecondary),
          side: const BorderSide(color: borderLight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData(brightness: Brightness.light).textTheme,
        ).copyWith(
          displayLarge: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.0,
            color: textPrimary,
          ),
          displayMedium: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: textPrimary,
          ),
          headlineLarge: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: textPrimary,
          ),
          headlineMedium: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
          titleLarge: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
          titleMedium: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
          bodyLarge: const TextStyle(
            fontSize: 17,
            height: 1.6,
            color: textSecondary,
          ),
          bodyMedium: const TextStyle(
            fontSize: 15,
            height: 1.6,
            color: textSecondary,
          ),
          bodySmall: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: textTertiary,
          ),
          labelLarge: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: bgElevated,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderLight, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderLight, width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primaryColor, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: error, width: 2),
          ),
          hintStyle: const TextStyle(color: textMuted),
          labelStyle: const TextStyle(color: textSecondary),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: bgElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
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
            return borderMedium;
          }),
        ),
      );

  /// Dark Theme
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: primaryLight,
          secondary: secondaryLight,
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
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: borderDark.withValues(alpha: 0.5)),
          ),
          margin: EdgeInsets.zero,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(
          backgroundColor: bgDark,
          foregroundColor: textDarkPrimary,
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
        ),
        dividerTheme: DividerThemeData(
          color: borderDark.withValues(alpha: 0.5),
          thickness: 1,
        ),
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          tileColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: bgDark,
          selectedItemColor: primaryLight,
          unselectedItemColor: textDarkTertiary,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: bgDark,
          selectedIconTheme: IconThemeData(color: primaryLight),
          selectedLabelTextStyle:
              TextStyle(color: primaryLight, fontWeight: FontWeight.w600),
          unselectedIconTheme: IconThemeData(color: textDarkTertiary),
          unselectedLabelTextStyle: TextStyle(color: textDarkTertiary),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: primaryLight,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryLight,
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 17,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryLight,
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            side: const BorderSide(color: primaryLight, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryLight,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: bgDarkElevated,
          labelStyle: const TextStyle(color: textDarkSecondary),
          side: BorderSide(color: borderDark.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ).copyWith(
          displayLarge: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.0,
            color: textDarkPrimary,
          ),
          displayMedium: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: textDarkPrimary,
          ),
          headlineLarge: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: textDarkPrimary,
          ),
          headlineMedium: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: textDarkPrimary,
          ),
          titleLarge: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: textDarkPrimary,
          ),
          titleMedium: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textDarkPrimary,
          ),
          bodyLarge: const TextStyle(
            fontSize: 17,
            height: 1.6,
            color: textDarkSecondary,
          ),
          bodyMedium: const TextStyle(
            fontSize: 15,
            height: 1.6,
            color: textDarkSecondary,
          ),
          bodySmall: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: textDarkSecondary.withValues(alpha: 0.7),
          ),
          labelLarge: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: textDarkPrimary,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: bgDarkCard,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderDark.withValues(alpha: 0.5), width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderDark.withValues(alpha: 0.5), width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primaryLight, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: error, width: 2),
          ),
          hintStyle: TextStyle(color: textDarkSecondary.withValues(alpha: 0.5)),
          labelStyle: const TextStyle(color: textDarkSecondary),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: bgDarkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
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
          color: primaryLight,
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

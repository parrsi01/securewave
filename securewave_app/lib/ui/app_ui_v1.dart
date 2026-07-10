import 'package:flutter/material.dart';

class AppUIv1 {
  static const background = Color(0xFF020712);
  static const surface = Color(0xFF071527);
  static const surfaceMuted = Color(0xFF0D2238);
  static const surfaceRaised = Color(0xFF102A44);
  static const graphite = Color(0xFFF8FBFF);
  static const graphiteMuted = Color(0xFFB6C8DE);
  static const line = Color(0xFF1B3554);
  static const lineStrong = Color(0xFF2A5C92);
  static const primary = Color(0xFF2F80FF);
  static const primarySoft = Color(0xFF082A55);
  static const safe = Color(0xFF53D39A);
  static const safeSoft = Color(0xFF0B2D25);
  static const amber = Color(0xFFF4B04B);
  static const amberSoft = Color(0xFF34270E);
  static const red = Color(0xFFFF6B6B);
  static const redSoft = Color(0xFF351417);
  static const secondary = Color(0xFFFFFFFF);
  static const secondarySoft = Color(0xFF172B43);

  static const radius = 10.0;
  static const radiusSmall = 8.0;
  static const maxWidth = 1160.0;
  static const mobileMax = 760.0;

  static ThemeData get theme {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: primary,
      onPrimary: Colors.white,
      secondary: secondary,
      surface: surface,
      onSurface: graphite,
      error: red,
      outline: line,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: null,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 25,
          height: 1.16,
          fontWeight: FontWeight.w700,
          color: graphite,
        ),
        titleLarge: TextStyle(
          fontSize: 19,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: graphite,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: graphite,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.42,
          color: graphite,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.38,
          color: graphiteMuted,
        ),
        bodySmall: TextStyle(
          fontSize: 12.5,
          height: 1.32,
          color: graphiteMuted,
        ),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: surface,
        foregroundColor: graphite,
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: graphite,
          minimumSize: const Size(0, 44),
          side: const BorderSide(color: lineStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: primary, width: 1.4),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: graphite,
          minimumSize: const Size.square(48),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: line),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: background,
        indicatorColor: primarySoft,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight:
                states.contains(WidgetState.selected) ? FontWeight.w700 : null,
            color: graphite,
          ),
        ),
      ),
    );
  }
}

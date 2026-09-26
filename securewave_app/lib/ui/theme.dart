import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _background = Color(0xFF03060D);
  static const _surface = Color(0xFF080F20);
  static const _blue = Color(0xFF00B4FF);
  static const _text = Color(0xFFD0E8FF);
  static const _muted = Color(0xFF8BA9C7);
  static const _border = Color(0xFF1A3060);
  static const _error = Color(0xFFFF8F86);

  static ThemeData get dark {
    final scheme = const ColorScheme.dark(
      primary: _blue,
      onPrimary: _background,
      surface: _surface,
      onSurface: _text,
      error: _error,
    ).copyWith(
      outline: _border,
      onSurfaceVariant: _muted,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: _background,
      fontFamily: 'SpaceGrotesk',
      appBarTheme: const AppBarTheme(
        backgroundColor: _background,
        foregroundColor: _text,
        centerTitle: false,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: _text,
          fontWeight: FontWeight.w700,
          fontSize: 24,
        ),
        titleLarge: TextStyle(
          color: _text,
          fontWeight: FontWeight.w600,
          fontSize: 20,
        ),
        titleMedium: TextStyle(
          color: _text,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
        bodyLarge: TextStyle(color: _text, fontSize: 16),
        bodyMedium: TextStyle(color: _muted, fontSize: 14),
        labelLarge: TextStyle(color: _text, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(color: _muted, fontSize: 13),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        hintStyle: const TextStyle(color: _muted),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _blue),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _error),
        ),
      ),
      dividerColor: _border,
    );
  }
}

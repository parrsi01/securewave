import 'package:flutter/material.dart';

class SecureWaveTokens {
  const SecureWaveTokens._();

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

  static const double radiusSm = 16;
  static const double radiusMd = 24;
  static const double radiusLg = 32;
  static const Duration animationFast = Duration(milliseconds: 180);
  static const Duration animationMedium = Duration(milliseconds: 320);
  static const Duration animationSlow = Duration(milliseconds: 480);

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Color(0xFF0C1730),
      Color(0xFF08111F),
      Color(0xFF060C17),
    ],
  );
}

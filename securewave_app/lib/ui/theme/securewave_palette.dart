import 'package:flutter/material.dart';

class SecureWavePalette {
  SecureWavePalette._();

  static const Color brand = Color(0xFF17716F);
  static const Color brandMid = Color(0xFF12595D);
  static const Color brandDeep = Color(0xFF0C2430);
  static const Color mint = Color(0xFF6FD6CD);
  static const Color frost = Color(0xFFDFF8F4);

  static const Color success = Color(0xFF2EC27E);
  static const Color warning = Color(0xFFF4B95D);
  static const Color danger = Color(0xFFFF6B62);

  static const Color lightBg = Color(0xFFF4F7F7);
  static const Color lightBgAlt = Color(0xFFEDF3F3);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceMuted = Color(0xFFF3F6F6);
  static const Color lightBorder = Color(0xFFD6E0E1);
  static const Color lightInk = Color(0xFF0D2530);
  static const Color lightMuted = Color(0xFF61767B);

  static const Color darkBg = Color(0xFF081218);
  static const Color darkBgAlt = Color(0xFF0D1B22);
  static const Color darkSurface = Color(0xFF0F2028);
  static const Color darkSurfaceMuted = Color(0xFF152831);
  static const Color darkBorder = Color(0xFF243942);
  static const Color darkInk = Color(0xFFE7F2F2);
  static const Color darkMuted = Color(0xFF95A9AE);

  static const Color graphDownload = Color(0xFF7BE8DA);
  static const Color graphUpload = Color(0xFF4FA6FF);
  static const Color graphGrid = Color(0xFF2A4B55);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF1D8480), brand, brandDeep],
  );

  static const LinearGradient connectGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF4CCFC5), brand, brandDeep],
  );

  static const LinearGradient connectedGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF74E5CF), Color(0xFF2DB38A), Color(0xFF0E5555)],
  );

  static const LinearGradient heroGradientLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFFF9FBFB), Color(0xFFEEF3F3)],
  );

  static const LinearGradient heroGradientDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF0A171D), Color(0xFF102229)],
  );

  static const LinearGradient shellBackgroundDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0xFF081118), Color(0xFF0B171E), Color(0xFF0D1D24)],
    stops: <double>[0, 0.45, 1],
  );

  static const LinearGradient shellBackgroundLight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0xFFF7FAFA), Color(0xFFF1F5F5), Color(0xFFEBF0F1)],
    stops: <double>[0, 0.5, 1],
  );
}

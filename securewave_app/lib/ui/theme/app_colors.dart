import 'package:flutter/material.dart';

/// SecureWave dark design tokens.
///
/// The implementation keeps the existing symbol names for compatibility with
/// the recently-added UI components, but the actual palette is now a calmer
/// SecureWave brand: deep slate surfaces, sea-glass teal as the primary accent,
/// and a cool blue secondary for depth.
class HtbColors {
  HtbColors._();

  // ── Primary Accent ────────────────────────────────────────────────────────

  static const Color neonGreen = Color(0xFF4DDFC9);
  static const Color neonGreenMuted = Color(0xFF2EAFA0);
  static const Color neonGreenGhost = Color(0x1A4DDFC9);
  static const Color neonGreenHover = Color(0x0F4DDFC9);

  // ── Secondary Accent ──────────────────────────────────────────────────────

  static const Color neonCyan = Color(0xFF7BB8FF);
  static const Color neonCyanMuted = Color(0xFF4E80D1);
  static const Color neonCyanGhost = Color(0x167BB8FF);

  // ── Backgrounds ───────────────────────────────────────────────────────────

  static const Color bg0 = Color(0xFF06131B);
  static const Color bg1 = Color(0xFF0A1A24);
  static const Color bg2 = Color(0xFF102633);
  static const Color bg3 = Color(0xFF163547);

  // ── Glass Surface Tokens ─────────────────────────────────────────────────

  static const Color glassFill = Color(0xD90A1A24);
  static const Color glassFillLight = Color(0xD9102633);
  static const Color glassBorderNeon = Color(0x334DDFC9);
  static const Color glassBorderDefault = Color(0x267BB8FF);
  static const Color glassBorderMuted = Color(0x14FFFFFF);

  // ── Text Colors ───────────────────────────────────────────────────────────

  static const Color textPrimary = Color(0xFFEAF6F7);
  static const Color textSecondary = Color(0xFFA0B8BF);
  static const Color textTertiary = Color(0xFF68818A);
  static const Color textInverse = Color(0xFF06131B);
  static const Color textMono = Color(0xFF9ED8FF);
  static const Color textHint = Color(0xFF4C6570);

  // ── Status Colors ─────────────────────────────────────────────────────────

  static const Color statusConnected = neonGreen;
  static const Color statusDisconnected = Color(0xFFFF7272);
  static const Color statusConnecting = Color(0xFFF6B74A);
  static const Color statusWarning = Color(0xFFFF9B4A);
  static const Color statusError = Color(0xFFFF7272);
  static const Color statusIdle = textTertiary;

  // ── Glow Colors ───────────────────────────────────────────────────────────

  static const Color glowGreen = Color(0x4D4DDFC9);
  static const Color glowGreenSoft = Color(0x224DDFC9);
  static const Color glowCyan = Color(0x337BB8FF);
  static const Color glowRed = Color(0x44FF7272);
  static const Color glowAmber = Color(0x44F6B74A);

  // ── Borders & Dividers ────────────────────────────────────────────────────

  static const Color border = Color(0xFF1A3242);
  static const Color borderActive = neonGreen;
  static const Color divider = Color(0xFF122635);

  // ── Miscellaneous ─────────────────────────────────────────────────────────

  static const Color scrim = Color(0xCC06131B);
  static const Color loadLow = neonGreen;
  static const Color loadMedium = statusConnecting;
  static const Color loadHigh = statusDisconnected;

  // ── ColorScheme Builder ───────────────────────────────────────────────────

  static ColorScheme darkScheme() {
    return ColorScheme.fromSeed(
      seedColor: neonGreen,
      brightness: Brightness.dark,
    ).copyWith(
      primary: neonGreen,
      onPrimary: textInverse,
      primaryContainer: neonGreenGhost,
      onPrimaryContainer: textPrimary,
      secondary: neonCyan,
      onSecondary: textInverse,
      secondaryContainer: neonCyanGhost,
      onSecondaryContainer: textPrimary,
      surface: bg1,
      onSurface: textPrimary,
      surfaceContainerLowest: bg0,
      surfaceContainerLow: bg0,
      surfaceContainer: bg1,
      surfaceContainerHigh: bg2,
      surfaceContainerHighest: bg3,
      onSurfaceVariant: textSecondary,
      outline: border,
      outlineVariant: divider,
      error: statusError,
      onError: textInverse,
      shadow: Colors.black,
      scrim: scrim,
      inverseSurface: textPrimary,
      onInverseSurface: bg0,
      inversePrimary: neonGreenMuted,
    );
  }
}

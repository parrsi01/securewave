import 'package:flutter/material.dart';

/// SecureWave dark design tokens.
///
/// The implementation keeps the existing symbol names for compatibility with
/// the recently-added UI components, but the actual palette is now a darker
/// SecureWave brand: near-black surfaces, electric blue as the lead accent,
/// and neon pink/purple for secondary energy.
class HtbColors {
  HtbColors._();

  // ── Primary Accent ────────────────────────────────────────────────────────

  static const Color neonGreen = Color(0xFF7BB8FF);
  static const Color neonGreenMuted = Color(0xFF4F8DFF);
  static const Color neonGreenGhost = Color(0x1A7BB8FF);
  static const Color neonGreenHover = Color(0x0F7BB8FF);

  // ── Secondary Accent ──────────────────────────────────────────────────────

  static const Color neonCyan = Color(0xFFFF5CF4);
  static const Color neonCyanMuted = Color(0xFF9B6BFF);
  static const Color neonCyanGhost = Color(0x1AFF5CF4);

  // ── Backgrounds ───────────────────────────────────────────────────────────

  static const Color bg0 = Color(0xFF050711);
  static const Color bg1 = Color(0xFF090D1A);
  static const Color bg2 = Color(0xFF111728);
  static const Color bg3 = Color(0xFF181F38);

  // ── Glass Surface Tokens ─────────────────────────────────────────────────

  static const Color glassFill = Color(0xD9090D1A);
  static const Color glassFillLight = Color(0xD9111728);
  static const Color glassBorderNeon = Color(0x337BB8FF);
  static const Color glassBorderDefault = Color(0x269B6BFF);
  static const Color glassBorderMuted = Color(0x14FFFFFF);

  // ── Text Colors ───────────────────────────────────────────────────────────

  static const Color textPrimary = Color(0xFFF2F5FF);
  static const Color textSecondary = Color(0xFFAAB5D6);
  static const Color textTertiary = Color(0xFF727A99);
  static const Color textInverse = Color(0xFF050711);
  static const Color textMono = Color(0xFFC4B9FF);
  static const Color textHint = Color(0xFF505B7E);

  // ── Status Colors ─────────────────────────────────────────────────────────

  static const Color statusConnected = neonGreen;
  static const Color statusDisconnected = Color(0xFFFF7272);
  static const Color statusConnecting = Color(0xFFF6B74A);
  static const Color statusWarning = Color(0xFFFF9B4A);
  static const Color statusError = Color(0xFFFF7272);
  static const Color statusIdle = textTertiary;

  // ── Glow Colors ───────────────────────────────────────────────────────────

  static const Color glowGreen = Color(0x4D7BB8FF);
  static const Color glowGreenSoft = Color(0x227BB8FF);
  static const Color glowCyan = Color(0x44FF5CF4);
  static const Color glowRed = Color(0x44FF7272);
  static const Color glowAmber = Color(0x44F6B74A);

  // ── Borders & Dividers ────────────────────────────────────────────────────

  static const Color border = Color(0xFF232B45);
  static const Color borderActive = neonGreen;
  static const Color divider = Color(0xFF171E33);

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

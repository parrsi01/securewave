import 'package:flutter/material.dart';

import '../design/app_colors.dart';

/// SecureWave dark design tokens.
///
/// Compatibility layer for older UI code that still references `HtbColors`.
/// The underlying palette is now the shared black-based SecureWave system:
/// softened blue primary accents with muted orchid / iris secondary energy.
class HtbColors {
  HtbColors._();

  // ── Primary Accent ───────────────────────────────────────────────────────

  static const Color accentPrimary = AppColors.primaryBright;
  static const Color accentPrimaryMuted = AppColors.primary;
  static const Color accentPrimaryGhost = AppColors.primaryGhost;
  static const Color accentPrimaryHover = Color(0x108EC5FF);

  // ── Secondary Accent ─────────────────────────────────────────────────────

  static const Color accentSecondary = AppColors.secondary;
  static const Color accentSecondaryMuted = AppColors.secondaryDark;
  static const Color accentSecondaryGhost = Color(0x148C74E6);

  // ── Backgrounds ───────────────────────────────────────────────────────────

  static const Color bg0 = AppColors.darkBackground;
  static const Color bg1 = AppColors.darkBackgroundWarm;
  static const Color bg2 = AppColors.darkSurface;
  static const Color bg3 = AppColors.darkSurfaceElevated;

  // ── Glass Surface Tokens ─────────────────────────────────────────────────

  static const Color glassFill = Color(0xD90B0B0F);
  static const Color glassFillLight = Color(0xD9111117);
  static const Color glassBorderNeon = Color(0x228EC5FF);
  static const Color glassBorderDefault = Color(0x188C74E6);
  static const Color glassBorderMuted = Color(0x1AFFFFFF);

  // ── Text Colors ───────────────────────────────────────────────────────────

  static const Color textPrimary = AppColors.darkInk;
  static const Color textSecondary = AppColors.darkInkMuted;
  static const Color textTertiary = AppColors.darkInkSoft;
  static const Color textInverse = AppColors.darkBackground;
  static const Color textMono = Color(0xFFCFC7E7);
  static const Color textHint = Color(0xFF6D6884);

  // ── Status Colors ─────────────────────────────────────────────────────────

  static const Color statusConnected = AppColors.success;
  static const Color statusDisconnected = AppColors.error;
  static const Color statusConnecting = AppColors.warning;
  static const Color statusWarning = Color(0xFFFFB454);
  static const Color statusError = AppColors.error;
  static const Color statusErrorDeep = AppColors.errorDark;
  static const Color statusIdle = textTertiary;

  // ── Glow Colors ───────────────────────────────────────────────────────────

  static const Color glowPrimary = Color(0x338EC5FF);
  static const Color glowPrimarySoft = Color(0x168EC5FF);
  static const Color glowSecondary = Color(0x28D887F5);
  static const Color glowRed = Color(0x36FF6A8B);
  static const Color glowAmber = Color(0x36FFB454);

  // ── Borders & Dividers ────────────────────────────────────────────────────

  static const Color border = AppColors.darkBorder;
  static const Color borderActive = accentPrimary;
  static const Color divider = Color(0xFF211F2B);

  // ── Miscellaneous ─────────────────────────────────────────────────────────

  static const Color scrim = Color(0xCC050508);
  static const Color loadLow = accentPrimary;
  static const Color loadMedium = statusConnecting;
  static const Color loadHigh = statusDisconnected;

  // ── ColorScheme Builder ───────────────────────────────────────────────────

  static ColorScheme darkScheme() {
    return AppColors.darkScheme().copyWith(
      primary: accentPrimary,
      onPrimary: textInverse,
      primaryContainer: bg3,
      onPrimaryContainer: textPrimary,
      secondary: accentSecondary,
      onSecondary: textInverse,
      secondaryContainer: accentSecondaryGhost,
      onSecondaryContainer: textPrimary,
      surface: bg2,
      onSurface: textPrimary,
      surfaceContainerLowest: bg0,
      surfaceContainerLow: bg1,
      surfaceContainer: bg2,
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
      inversePrimary: accentPrimaryMuted,
    );
  }
}

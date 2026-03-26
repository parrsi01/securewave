import 'package:flutter/material.dart';

import '../design/app_colors.dart';

/// SecureWave dark design tokens.
///
/// Compatibility layer for older UI code that still references `HtbColors`.
/// The underlying palette is now the shared black-based SecureWave system:
/// neon blue primary accents with pink and purple secondary energy.
class HtbColors {
  HtbColors._();

  // ── Primary Accent ───────────────────────────────────────────────────────

  static const Color accentPrimary = AppColors.primaryBright;
  static const Color accentPrimaryMuted = AppColors.primary;
  static const Color accentPrimaryGhost = AppColors.primaryGhost;
  static const Color accentPrimaryHover = Color(0x124CC9FF);

  // ── Secondary Accent ─────────────────────────────────────────────────────

  static const Color accentSecondary = AppColors.secondary;
  static const Color accentSecondaryMuted = AppColors.secondaryDark;
  static const Color accentSecondaryGhost = Color(0x1AFF2BD6);

  // ── Backgrounds ───────────────────────────────────────────────────────────

  static const Color bg0 = AppColors.darkBackground;
  static const Color bg1 = AppColors.darkBackgroundWarm;
  static const Color bg2 = AppColors.darkSurface;
  static const Color bg3 = AppColors.darkSurfaceElevated;

  // ── Glass Surface Tokens ─────────────────────────────────────────────────

  static const Color glassFill = Color(0xD90B0B0F);
  static const Color glassFillLight = Color(0xD9111117);
  static const Color glassBorderNeon = Color(0x334CC9FF);
  static const Color glassBorderDefault = Color(0x267A5CFF);
  static const Color glassBorderMuted = Color(0x1AFFFFFF);

  // ── Text Colors ───────────────────────────────────────────────────────────

  static const Color textPrimary = AppColors.darkInk;
  static const Color textSecondary = AppColors.darkInkMuted;
  static const Color textTertiary = AppColors.darkInkSoft;
  static const Color textInverse = AppColors.darkBackground;
  static const Color textMono = Color(0xFFD2C8FF);
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

  static const Color glowPrimary = Color(0x4D4CC9FF);
  static const Color glowPrimarySoft = Color(0x224CC9FF);
  static const Color glowSecondary = Color(0x44FF2BD6);
  static const Color glowRed = Color(0x44FF6A8B);
  static const Color glowAmber = Color(0x44FFB454);

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

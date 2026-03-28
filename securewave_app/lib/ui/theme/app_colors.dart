import 'package:flutter/material.dart';

import '../design/app_colors.dart';

/// SecureWave shared dark design tokens.
///
/// Legacy names are retained for compatibility, but the values resolve to one
/// dark plum + single neon purple system.
class HtbColors {
  HtbColors._();

  // ── Primary Accent (Neon Purple) ──────────────────────────────────────────

  static const Color neonPurple = AppColors.primary;
  static const Color neonPurpleMuted = AppColors.primaryDark;
  static const Color neonPurpleGhost = AppColors.primaryGhost;
  static const Color neonPurpleHover = AppColors.primaryWash;

  static const Color neonLavender = AppColors.primaryBright;
  static const Color neonLavenderMuted = AppColors.primaryDark;
  static const Color neonLavenderGhost = AppColors.primaryWash;

  // ── Accent aliases (used by newer screens) ────────────────────────────────

  static const Color accentPrimary = AppColors.primary;
  static const Color accentPrimaryMuted = AppColors.primaryDark;
  static const Color accentPrimaryGhost = AppColors.primaryGhost;
  static const Color accentPrimaryHover = AppColors.primaryWash;

  static const Color accentSecondary = AppColors.primaryBright;
  static const Color accentSecondaryMuted = AppColors.primaryDark;
  static const Color accentSecondaryGhost = AppColors.primaryWash;

  static const Color accentTertiary = AppColors.primaryBright;

  static const Color bg0 = AppColors.background;
  static const Color bg1 = AppColors.backgroundWarm;
  static const Color bg2 = AppColors.surfaceMuted;
  static const Color bg3 = AppColors.surfaceElevated;

  static const Color panelSunken = AppColors.surfaceSunken;
  static const Color panelBase = AppColors.surfaceBase;
  static const Color panelRaised = AppColors.surfaceRaised;
  static const Color panelFloating = AppColors.surfaceFloating;
  static const Color panelOverlay = AppColors.surfaceOverlay;

  // ── Glass Surface Tokens ─────────────────────────────────────────────────

  static const Color glassFill = Color(0xE61E1535);
  static const Color glassFillLight = Color(0xEA291C47);
  static const Color glassBorderNeon = Color(0x337A5CFF);
  static const Color glassBorderDefault = AppColors.borderStrong;
  static const Color glassBorderMuted = Color(0x14EDE6FF);

  // ── Text Colors ───────────────────────────────────────────────────────────

  static const Color textPrimary = AppColors.ink;
  static const Color textSecondary = AppColors.inkMuted;
  static const Color textTertiary = AppColors.inkSoft;
  static const Color textInverse = AppColors.ink;
  static const Color textMono = Color(0xFFD8CCFF);
  static const Color textHint = Color(0xFF6B5D8A);

  // ── Status Colors ─────────────────────────────────────────────────────────

  static const Color statusConnected = AppColors.success;
  static const Color statusDisconnected = Color(0xFFFF4D6A);
  static const Color statusConnecting = Color(0xFFFFB454);
  static const Color statusWarning = Color(0xFFFF9B4A);
  static const Color statusError = Color(0xFFFF4D6A);
  static const Color statusIdle = textTertiary;

  // ── Glow Colors ───────────────────────────────────────────────────────────

  static const Color glowPurple = Color(0x337A5CFF);
  static const Color glowPurpleSoft = Color(0x187A5CFF);
  static const Color glowLavender = Color(0x267A5CFF);
  static const Color glowRed = Color(0x44FF4D6A);
  static const Color glowAmber = Color(0x44FFB454);

  // Semantic glow aliases (used by newer components)
  static const Color glowPrimary = Color(0x337A5CFF);
  static const Color glowPrimarySoft = Color(0x1A7A5CFF);
  static const Color glowSecondary = glowPrimarySoft;

  // Legacy aliases
  static const Color glowGreen = glowPurple;
  static const Color glowGreenSoft = glowPurpleSoft;
  static const Color glowCyan = glowLavender;
  static const Color statusErrorDeep = AppColors.errorDark;

  // ── Borders & Dividers ────────────────────────────────────────────────────

  static const Color border = AppColors.border;
  static const Color borderSubtle = AppColors.borderSubtle;
  static const Color borderStrong = AppColors.borderStrong;
  static const Color borderAccent = AppColors.borderAccent;
  static const Color borderActive = accentPrimary;
  static const Color divider = Color(0xFF2A1F4A);

  // ── Miscellaneous ─────────────────────────────────────────────────────────

  static const Color scrim = Color(0xCC0E0818);
  static const Color loadLow = accentPrimary;
  static const Color loadMedium = statusConnecting;
  static const Color loadHigh = statusDisconnected;

  // ── ColorScheme Builder ───────────────────────────────────────────────────

  static ColorScheme darkScheme() {
    return ColorScheme.fromSeed(
      seedColor: accentPrimary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: accentPrimary,
      onPrimary: textInverse,
      primaryContainer: AppColors.primaryDeep,
      onPrimaryContainer: textPrimary,
      secondary: accentSecondary,
      onSecondary: textInverse,
      secondaryContainer: AppColors.primaryDeep,
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
      shadow: const Color(0xFF060410),
      scrim: scrim,
      inverseSurface: textPrimary,
      onInverseSurface: bg0,
      inversePrimary: accentPrimaryMuted,
    );
  }
}

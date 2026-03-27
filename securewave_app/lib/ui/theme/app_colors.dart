import 'package:flutter/material.dart';

import '../design/app_colors.dart';

/// SecureWave design tokens — pure purple dark-to-light hue.
///
/// Primary: neon purple (#7A5CFF). Secondary: lavender (#B794FF).
/// Dark plum surfaces. No cyan/blue.
class HtbColors {
  HtbColors._();

  // ── Primary Accent (Neon Purple) ──────────────────────────────────────────

  static const Color accentPrimary = AppColors.primary;           // #7A5CFF
  static const Color accentPrimaryMuted = AppColors.primaryDark;  // #5A3FCC
  static const Color accentPrimaryGhost = AppColors.primaryGhost;
  static const Color accentPrimaryHover = AppColors.primaryWash;

  // ── Secondary Accent (Lavender) ───────────────────────────────────────────

  static const Color accentSecondary = AppColors.secondary;           // #B794FF
  static const Color accentSecondaryMuted = AppColors.secondaryDark;  // #9A72FF
  static const Color accentSecondaryGhost = AppColors.secondaryWash;

  // ── Tertiary Accent (Neon Pink) ───────────────────────────────────────────

  static const Color accentTertiary = AppColors.tertiary;  // #FF2BD6

  // ── Backgrounds (dark plum ramp) ─────────────────────────────────────────

  static const Color bg0 = AppColors.background;      // #0E0818
  static const Color bg1 = AppColors.backgroundWarm;  // #160F26
  static const Color bg2 = AppColors.surfaceMuted;    // #1E1535
  static const Color bg3 = AppColors.surfaceElevated; // #291C47

  // ── Glass Surface Tokens ─────────────────────────────────────────────────

  // dark plum @ 88% opacity
  static const Color glassFill = Color(0xE01A1130);
  static const Color glassFillLight = Color(0xE6201840);
  // purple neon border
  static const Color glassBorderNeon = Color(0x4D7A5CFF);
  static const Color glassBorderDefault = Color(0x337A5CFF);
  static const Color glassBorderMuted = Color(0x1AEDE6FF);

  // ── Text Colors (lavender-white ramp) ─────────────────────────────────────

  static const Color textPrimary = AppColors.ink;       // #EDE6FF
  static const Color textSecondary = AppColors.inkMuted; // #BAAFD
  static const Color textTertiary = AppColors.inkSoft;  // #8070A8
  // textInverse: used on bright neon buttons — dark plum
  static const Color textInverse = Color(0xFF0E0818);
  // textMono: lavender for monospace labels
  static const Color textMono = Color(0xFFD4C6FF);
  static const Color textHint = Color(0xFF6D5E96);

  // ── Status Colors ─────────────────────────────────────────────────────────

  static const Color statusConnected = AppColors.success;    // #9A72FF lavender
  static const Color statusDisconnected = AppColors.error;   // #FF4D6A
  static const Color statusConnecting = AppColors.warning;   // #FFB454
  static const Color statusWarning = AppColors.warning;
  static const Color statusError = AppColors.error;
  static const Color statusErrorDeep = AppColors.errorDark;
  static const Color statusIdle = textTertiary;

  // ── Glow Colors ───────────────────────────────────────────────────────────

  // neon purple glow
  static const Color glowPrimary = Color(0x527A5CFF);
  static const Color glowPrimarySoft = Color(0x2C7A5CFF);
  // lavender glow
  static const Color glowSecondary = Color(0x30B794FF);
  // pink accent glow
  static const Color glowTertiary = Color(0x28FF2BD6);
  // status glows
  static const Color glowRed = Color(0x44FF4D6A);
  static const Color glowAmber = Color(0x44FFB454);

  // ── Borders & Dividers ────────────────────────────────────────────────────

  static const Color border = AppColors.border;         // #3D2D66
  static const Color borderActive = accentPrimary;
  static const Color divider = Color(0xFF2E1F52);

  // ── Miscellaneous ─────────────────────────────────────────────────────────

  static const Color scrim = Color(0xCC0A0612);
  static const Color loadLow = accentPrimary;
  static const Color loadMedium = statusConnecting;
  static const Color loadHigh = statusDisconnected;

  // ── ColorScheme Builder ───────────────────────────────────────────────────

  static ColorScheme lightScheme() {
    return AppColors.lightScheme().copyWith(
      primary: accentPrimary,
      onPrimary: textInverse,
      primaryContainer: AppColors.primaryLight,
      onPrimaryContainer: textPrimary,
      secondary: accentSecondary,
      onSecondary: textInverse,
      secondaryContainer: AppColors.secondaryLight,
      onSecondaryContainer: textPrimary,
      tertiary: accentTertiary,
      onTertiary: textInverse,
      surface: bg0,
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
      shadow: const Color(0xFF0A0612),
      scrim: scrim,
      inverseSurface: textPrimary,
      onInverseSurface: bg0,
      inversePrimary: accentSecondary,
    );
  }

  // darkScheme() kept for compile compatibility — returns same dark scheme.
  static ColorScheme darkScheme() => lightScheme();
}

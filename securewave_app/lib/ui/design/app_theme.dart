import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_motion.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// SecureWave Material 3 theme system — v2.
///
/// Provides full light + dark themes with shadow-based elevation,
/// teal-tinted surfaces, and polished component overrides.
class AppTheme {
  AppTheme._();

  // ── Public Entry Points ──────────────────────────────────────────────────

  static ThemeData lightTheme() => _build(Brightness.light);
  static ThemeData darkTheme() => _build(Brightness.dark);

  // ── Theme Builder ────────────────────────────────────────────────────────

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme =
        isDark ? AppColors.darkScheme() : AppColors.lightScheme();

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
    );

    final textTheme = AppTypography.textTheme(base.textTheme, isDark: isDark);

    final scaffoldBg = isDark ? AppColors.darkBackground : AppColors.background;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final mutedSurface =
        isDark ? AppColors.darkSurfaceMuted : AppColors.surfaceMuted;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.border;
    final inkColor = isDark ? AppColors.darkInk : AppColors.ink;
    final inkMuted = isDark ? AppColors.darkInkMuted : AppColors.inkMuted;
    final inkSoft = isDark ? AppColors.darkInkSoft : AppColors.inkSoft;
    final primaryColor = isDark ? AppColors.primaryBright : AppColors.primary;
    final primaryLight = isDark
        ? AppColors.primaryDeep.withValues(alpha: 0.5)
        : AppColors.primaryLight;

    return base.copyWith(
      scaffoldBackgroundColor: scaffoldBg,
      dividerColor: borderColor,
      textTheme: textTheme,

      // ── AppBar ──────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: inkColor,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),

      // ── Card ────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXXL),
          side: BorderSide(color: borderColor, width: 0.5),
        ),
        margin: EdgeInsets.zero,
        shadowColor: Colors.transparent,
      ),

      // ── Input Decoration ─────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: mutedSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
          borderSide: BorderSide(color: borderColor, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
          borderSide: BorderSide(color: borderColor, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
          borderSide: BorderSide(color: primaryColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space4,
        ),
        hintStyle: TextStyle(color: inkSoft, fontWeight: FontWeight.w400),
        prefixIconColor: inkSoft,
        suffixIconColor: inkSoft,
      ),

      // ── Filled Button ─────────────────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space5,
            vertical: AppSpacing.space4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.1,
          ),
        ),
      ),

      // ── Outlined Button ───────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: BorderSide(color: borderColor, width: 1),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space5,
            vertical: AppSpacing.space4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          ),
          textStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: primaryColor,
          ),
        ),
      ),

      // ── Text Button ───────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space3,
            vertical: AppSpacing.space2,
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),

      // ── List Tiles ────────────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        iconColor: primaryColor,
        textColor: inkColor,
        tileColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        ),
      ),

      // ── Switch ────────────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return isDark ? AppColors.darkInkSoft : AppColors.inkSoft;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primaryColor;
          return isDark ? AppColors.darkSurfaceMuted : AppColors.surfaceMuted;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      // ── Navigation Bar (mobile bottom) ───────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
        indicatorColor: isDark
            ? AppColors.primaryBright.withValues(alpha: 0.18)
            : AppColors.primaryLight,
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: primaryColor);
          }
          return IconThemeData(color: inkSoft);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return textTheme.labelSmall?.copyWith(
              color: primaryColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            );
          }
          return textTheme.labelSmall?.copyWith(
            color: inkSoft,
            fontWeight: FontWeight.w500,
          );
        }),
      ),

      // ── Navigation Rail (tablet) ──────────────────────────────────────────
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: isDark
            ? AppColors.primaryBright.withValues(alpha: 0.18)
            : AppColors.primaryLight,
        elevation: 0,
        selectedIconTheme: IconThemeData(color: primaryColor),
        unselectedIconTheme: IconThemeData(color: inkSoft),
        selectedLabelTextStyle: textTheme.labelSmall?.copyWith(
          color: primaryColor,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: textTheme.labelSmall?.copyWith(
          color: inkSoft,
        ),
      ),

      // ── Dialog ────────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXXL),
          side: BorderSide(color: borderColor, width: 0.5),
        ),
        titleTextStyle:
            textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: inkMuted),
      ),

      // ── Bottom Sheet ──────────────────────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusXXL),
          ),
          side: BorderSide(color: borderColor, width: 0.5),
        ),
        dragHandleColor: inkSoft.withValues(alpha: 0.4),
        dragHandleSize: const Size(36, 4),
        showDragHandle: true,
      ),

      // ── Snack Bar ─────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.darkSurfaceElevated : AppColors.ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space4,
        ),
      ),

      // ── Progress Indicators ───────────────────────────────────────────────
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primaryColor,
        linearTrackColor: primaryLight,
        circularTrackColor: primaryLight,
        linearMinHeight: 3,
      ),

      // ── Chips ─────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: mutedSurface,
        selectedColor: primaryLight,
        labelStyle: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space3,
          vertical: AppSpacing.space1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          side: BorderSide(color: borderColor, width: 0.5),
        ),
      ),

      // ── Expansion Tile ───────────────────────────────────────────────────
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        iconColor: inkSoft,
        collapsedIconColor: inkSoft,
        textColor: inkColor,
        collapsedTextColor: inkColor,
        shape: const Border(),
        collapsedShape: const Border(),
      ),

      // ── Page Transitions ──────────────────────────────────────────────────
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeSlidePageTransitionsBuilder(),
          TargetPlatform.linux: FadeSlidePageTransitionsBuilder(),
          TargetPlatform.windows: FadeSlidePageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeSlidePageTransitionsBuilder(),
        },
      ),
    );
  }

  // ── Shadow Helpers ────────────────────────────────────────────────────────

  static List<BoxShadow> shadowSm(bool isDark) => isDark
      ? [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ]
      : [
          BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ];

  static List<BoxShadow> shadowMd(bool isDark) => isDark
      ? [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 24,
              offset: const Offset(0, 6))
        ]
      : [
          BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 6))
        ];
}

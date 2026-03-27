// =============================================================================
// CHANGELOG
// =============================================================================
// v4.1.0 (2026-03-26) — Strict neon dark color transformation
//   - Preserved stable layout and component structure
//   - Enforced near-black surfaces (#0B0B0F / #111117 / #1A1A22)
//   - Enforced neon accent system: blue (#4CC9FF), purple (#7A5CFF),
//     pink (#FF2BD6)
//   - Removed remaining legacy palette references from the shared
//     Material theme docs
// v4.0.0 (2026-03-26) — Neon dark mode: blue + purple palette
//   - Full dark theme: near-black surfaces (#0B0B0F), neon blue primary
//     (#4CC9FF), neon purple secondary (#7A5CFF), light text (#E8E6F0)
//   - HtbTheme.dark() now produces a true dark Material3 theme
//   - SystemUiOverlayStyle: dark status bar with light icons
//   - Input fill: bg2 (#1A1A22), focusedBorder: accentPrimary (#4CC9FF)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Theme Extensions
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class HtbGradients extends ThemeExtension<HtbGradients> {
  const HtbGradients({
    required this.shellBackground,
    required this.connectedGlow,
    required this.ctaButton,
    required this.neonEdge,
  });

  final Gradient shellBackground;
  final Gradient connectedGlow;
  final Gradient ctaButton;
  final Gradient neonEdge;

  static const HtbGradients dark = HtbGradients(
    shellBackground: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [HtbColors.bg0, HtbColors.bg1],
    ),
    connectedGlow: RadialGradient(
      center: Alignment.topCenter,
      radius: 1.1,
      colors: [HtbColors.glowPrimarySoft, HtbColors.bg0],
    ),
    ctaButton: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        HtbColors.accentPrimary,
        HtbColors.accentPrimaryMuted,
      ],
    ),
    neonEdge: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        HtbColors.accentPrimary,
        HtbColors.accentSecondary,
      ],
    ),
  );

  @override
  HtbGradients copyWith({
    Gradient? shellBackground,
    Gradient? connectedGlow,
    Gradient? ctaButton,
    Gradient? neonEdge,
  }) {
    return HtbGradients(
      shellBackground: shellBackground ?? this.shellBackground,
      connectedGlow: connectedGlow ?? this.connectedGlow,
      ctaButton: ctaButton ?? this.ctaButton,
      neonEdge: neonEdge ?? this.neonEdge,
    );
  }

  @override
  HtbGradients lerp(covariant ThemeExtension<HtbGradients>? other, double t) {
    if (other is! HtbGradients) return this;
    return HtbGradients(
      shellBackground:
          Gradient.lerp(shellBackground, other.shellBackground, t) ??
              shellBackground,
      connectedGlow:
          Gradient.lerp(connectedGlow, other.connectedGlow, t) ?? connectedGlow,
      ctaButton: Gradient.lerp(ctaButton, other.ctaButton, t) ?? ctaButton,
      neonEdge: Gradient.lerp(neonEdge, other.neonEdge, t) ?? neonEdge,
    );
  }
}

@immutable
class HtbSemanticColors extends ThemeExtension<HtbSemanticColors> {
  const HtbSemanticColors({
    required this.connected,
    required this.disconnected,
    required this.connecting,
    required this.warning,
    required this.error,
    required this.mono,
    required this.muted,
  });

  final Color connected;
  final Color disconnected;
  final Color connecting;
  final Color warning;
  final Color error;
  final Color mono;
  final Color muted;

  static const HtbSemanticColors dark = HtbSemanticColors(
    connected: HtbColors.statusConnected,
    disconnected: HtbColors.statusDisconnected,
    connecting: HtbColors.statusConnecting,
    warning: HtbColors.statusWarning,
    error: HtbColors.statusError,
    mono: HtbColors.textMono,
    muted: HtbColors.textTertiary,
  );

  @override
  HtbSemanticColors copyWith({
    Color? connected,
    Color? disconnected,
    Color? connecting,
    Color? warning,
    Color? error,
    Color? mono,
    Color? muted,
  }) {
    return HtbSemanticColors(
      connected: connected ?? this.connected,
      disconnected: disconnected ?? this.disconnected,
      connecting: connecting ?? this.connecting,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      mono: mono ?? this.mono,
      muted: muted ?? this.muted,
    );
  }

  @override
  HtbSemanticColors lerp(
    covariant ThemeExtension<HtbSemanticColors>? other,
    double t,
  ) {
    if (other is! HtbSemanticColors) return this;
    return HtbSemanticColors(
      connected: Color.lerp(connected, other.connected, t) ?? connected,
      disconnected:
          Color.lerp(disconnected, other.disconnected, t) ?? disconnected,
      connecting: Color.lerp(connecting, other.connecting, t) ?? connecting,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      error: Color.lerp(error, other.error, t) ?? error,
      mono: Color.lerp(mono, other.mono, t) ?? mono,
      muted: Color.lerp(muted, other.muted, t) ?? muted,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BuildContext Extension
// ─────────────────────────────────────────────────────────────────────────────

extension HtbThemeContext on BuildContext {
  HtbGradients get htbGradients =>
      Theme.of(this).extension<HtbGradients>() ?? HtbGradients.dark;

  HtbSemanticColors get htbColors =>
      Theme.of(this).extension<HtbSemanticColors>() ?? HtbSemanticColors.dark;
}

// ─────────────────────────────────────────────────────────────────────────────
// HtbTheme — entry point
// ─────────────────────────────────────────────────────────────────────────────

class HtbTheme {
  HtbTheme._();

  /// Returns the SecureWave strict neon dark theme.
  static ThemeData dark() {
    final colorScheme = HtbColors.darkScheme();
    final textTheme = AppTypography.textTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: HtbColors.bg0,

      // ── AppBar ────────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: HtbColors.bg0,
        foregroundColor: HtbColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.textTheme().titleMedium?.copyWith(
              color: HtbColors.textPrimary,
              letterSpacing: 0,
            ),
        iconTheme: const IconThemeData(
          color: HtbColors.textSecondary,
          size: AppTokens.iconM,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
        ),
      ),

      // ── Card ──────────────────────────────────────────────────────────────
      cardTheme: const CardThemeData(
        color: HtbColors.bg1,
        shadowColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppTokens.brCard,
          side: BorderSide(
            color: HtbColors.glassBorderDefault,
            width: AppTokens.borderWidth,
          ),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),

      // ── ElevatedButton ────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: HtbColors.accentPrimary,
          foregroundColor: HtbColors.textInverse,
          disabledBackgroundColor: HtbColors.accentPrimaryGhost,
          disabledForegroundColor: HtbColors.textTertiary,
          minimumSize: const Size(
            AppTokens.buttonMinWidth,
            AppTokens.buttonHeightM,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.paddingL,
            vertical: AppTokens.paddingS,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppTokens.brMedium),
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: AppTypography.textTheme().labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: HtbColors.accentPrimary,
          foregroundColor: HtbColors.textInverse,
          disabledBackgroundColor: HtbColors.accentPrimaryGhost,
          disabledForegroundColor: HtbColors.textTertiary,
          minimumSize: const Size(
            AppTokens.buttonMinWidth,
            AppTokens.buttonHeightM,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.paddingL,
            vertical: AppTokens.paddingS,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppTokens.brMedium),
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: AppTypography.textTheme().labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
        ),
      ),

      // ── OutlinedButton ────────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: HtbColors.textPrimary,
          disabledForegroundColor: HtbColors.textTertiary,
          minimumSize: const Size(
            AppTokens.buttonMinWidth,
            AppTokens.buttonHeightM,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.paddingL,
            vertical: AppTokens.paddingS,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppTokens.brMedium),
          side: const BorderSide(
            color: HtbColors.border,
            width: AppTokens.neonBorderWidth,
          ),
          textStyle: AppTypography.textTheme().labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
        ),
      ),

      // ── TextButton ────────────────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: HtbColors.accentSecondary,
          textStyle: AppTypography.textTheme().labelLarge,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.paddingM,
            vertical: AppTokens.paddingS,
          ),
        ),
      ),

      // ── Input Decoration ─────────────────────────────────────────────────
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: HtbColors.bg2,
        hintStyle: TextStyle(color: HtbColors.textHint),
        labelStyle: TextStyle(color: HtbColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: AppTokens.brMedium,
          borderSide: BorderSide(
            color: HtbColors.border,
            width: AppTokens.borderWidth,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppTokens.brMedium,
          borderSide: BorderSide(
            color: HtbColors.border,
            width: AppTokens.borderWidth,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppTokens.brMedium,
          borderSide: BorderSide(
            color: HtbColors.accentPrimary,
            width: AppTokens.neonBorderWidth,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppTokens.brMedium,
          borderSide: BorderSide(
            color: HtbColors.statusError,
            width: AppTokens.neonBorderWidth,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppTokens.brMedium,
          borderSide: BorderSide(
            color: HtbColors.statusError,
            width: AppTokens.neonBorderWidth,
          ),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppTokens.paddingM,
          vertical: AppTokens.paddingM,
        ),
      ),

      // ── Chip ─────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: HtbColors.bg2,
        selectedColor: HtbColors.accentPrimaryGhost,
        disabledColor: HtbColors.bg1,
        labelStyle: AppTypography.textTheme().labelMedium?.copyWith(
              color: HtbColors.textSecondary,
            ),
        secondaryLabelStyle: AppTypography.textTheme().labelMedium?.copyWith(
              color: HtbColors.accentPrimary,
            ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.paddingS,
          vertical: AppTokens.paddingXS,
        ),
        shape: const StadiumBorder(
          side: BorderSide(
            color: HtbColors.glassBorderDefault,
            width: AppTokens.borderWidth,
          ),
        ),
        side: const BorderSide(
          color: HtbColors.glassBorderDefault,
          width: AppTokens.borderWidth,
        ),
        elevation: 0,
        pressElevation: 0,
      ),

      // ── NavigationDrawer ──────────────────────────────────────────────────
      drawerTheme: const DrawerThemeData(
        backgroundColor: HtbColors.bg1,
        scrimColor: HtbColors.scrim,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(AppTokens.radiusLarge),
            bottomRight: Radius.circular(AppTokens.radiusLarge),
          ),
        ),
      ),

      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: HtbColors.bg1,
        elevation: 0,
        indicatorColor: HtbColors.accentPrimaryGhost,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: AppTokens.brMedium,
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppTypography.textTheme().labelLarge?.copyWith(
                  color: HtbColors.accentPrimary,
                  fontWeight: FontWeight.w700,
                );
          }
          return AppTypography.textTheme().labelLarge?.copyWith(
                color: HtbColors.textSecondary,
              );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: HtbColors.accentPrimary);
          }
          return const IconThemeData(color: HtbColors.textSecondary);
        }),
      ),

      // ── Icon ─────────────────────────────────────────────────────────────
      iconTheme: const IconThemeData(
        color: HtbColors.textSecondary,
        size: AppTokens.iconM,
      ),
      primaryIconTheme: const IconThemeData(
        color: HtbColors.accentPrimary,
        size: AppTokens.iconM,
      ),

      // ── Divider ───────────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: HtbColors.divider,
        thickness: 1,
        space: 1,
      ),

      // ── ProgressIndicator ─────────────────────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: HtbColors.accentPrimary,
        linearTrackColor: HtbColors.bg2,
        circularTrackColor: HtbColors.bg2,
      ),

      // ── Tooltip ──────────────────────────────────────────────────────────
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: HtbColors.bg2,
          borderRadius: AppTokens.brSmall,
          border: Border.all(color: HtbColors.border),
        ),
        textStyle: AppTypography.textTheme().bodySmall?.copyWith(
              color: HtbColors.textPrimary,
            ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.paddingS,
          vertical: AppTokens.paddingXS,
        ),
      ),

      // ── SnackBar ─────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: HtbColors.bg2,
        contentTextStyle: AppTypography.textTheme().bodyMedium?.copyWith(
              color: HtbColors.textPrimary,
            ),
        shape: const RoundedRectangleBorder(borderRadius: AppTokens.brMedium),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),

      // ── Dialog ───────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: HtbColors.bg1,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppTokens.radiusLarge),
          ),
          side: BorderSide(
            color: HtbColors.glassBorderDefault,
            width: AppTokens.borderWidth,
          ),
        ),
        titleTextStyle: AppTypography.textTheme().titleLarge?.copyWith(
              color: HtbColors.textPrimary,
              letterSpacing: 0.5,
            ),
        contentTextStyle: AppTypography.textTheme().bodyMedium?.copyWith(
              color: HtbColors.textSecondary,
            ),
      ),

      // ── BottomSheet ───────────────────────────────────────────────────────
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: HtbColors.bg2,
        modalBackgroundColor: HtbColors.bg2,
        elevation: 0,
        modalElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.radiusLarge),
          ),
          side: BorderSide(
            color: HtbColors.glassBorderDefault,
            width: AppTokens.borderWidth,
          ),
        ),
      ),

      // ── ListTile ─────────────────────────────────────────────────────────
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: HtbColors.accentPrimaryGhost,
        selectedColor: HtbColors.accentPrimary,
        iconColor: HtbColors.textSecondary,
        textColor: HtbColors.textPrimary,
        titleTextStyle: AppTypography.textTheme().bodyMedium?.copyWith(
              color: HtbColors.textPrimary,
            ),
        subtitleTextStyle: AppTypography.textTheme().bodySmall?.copyWith(
              color: HtbColors.textSecondary,
            ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.paddingM,
          vertical: AppTokens.paddingXS,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppTokens.brCard),
      ),

      // ── Switch ────────────────────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return HtbColors.bg0;
          }
          return HtbColors.textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return HtbColors.accentPrimary;
          }
          return HtbColors.bg2;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return HtbColors.accentPrimary;
          }
          return HtbColors.border;
        }),
      ),

      // ── Theme Extensions ──────────────────────────────────────────────────
      extensions: const <ThemeExtension<dynamic>>[
        HtbGradients.dark,
        HtbSemanticColors.dark,
      ],
    );
  }
}

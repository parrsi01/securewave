import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design/app_colors.dart';
import '../design/app_spacing.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Spacing / Radius / Breakpoints — delegation wrappers
// ─────────────────────────────────────────────────────────────────────────────

class SecureWaveSpacing {
  SecureWaveSpacing._();

  static const double xs = AppSpacing.space1;
  static const double sm = AppSpacing.space2;
  static const double md = AppSpacing.space3;
  static const double base = AppSpacing.space4;
  static const double lg = AppSpacing.space5;
  static const double xl = AppSpacing.space6;
  static const double xxl = AppSpacing.space7;
  static const double xxxl = AppSpacing.space8;
  static const double hero = AppSpacing.space9;

  static const double pagePadding = AppSpacing.pagePadding;
  static const double cardPadding = AppSpacing.cardPadding;
  static const double sectionGap = AppSpacing.sectionGap;
  static const double itemGap = AppSpacing.itemGap;
}

class SecureWaveRadius {
  SecureWaveRadius._();

  static const double xs = AppSpacing.radiusXS;
  static const double sm = AppSpacing.radiusS;
  static const double md = AppSpacing.radiusM;
  static const double lg = AppSpacing.radiusL;
  static const double xl = AppSpacing.radiusXL;
  static const double xxl = AppSpacing.radiusXXL;
  static const double full = AppSpacing.radiusFull;
}

class SecureWaveBreakpoints {
  SecureWaveBreakpoints._();

  static const double mobile = AppSpacing.mobileBreakpoint;
  static const double tablet = AppSpacing.tabletBreakpoint;
  static const double authMaxWidth = AppSpacing.authMaxWidth;
  static const double contentMaxWidth = AppSpacing.contentMaxWidth;
  static const double sidebarWidth = AppSpacing.sidebarWidth;
  static const double railWidth = AppSpacing.railWidth;
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme Extensions
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class SecureWaveGradients extends ThemeExtension<SecureWaveGradients> {
  const SecureWaveGradients({
    required this.brandGradient,
    required this.connectedGradient,
    required this.connectGradient,
    required this.shellBackground,
  });

  final Gradient brandGradient;
  final Gradient connectedGradient;
  final Gradient connectGradient;
  final Gradient shellBackground;

  static const SecureWaveGradients light = SecureWaveGradients(
    brandGradient: AppColors.brandGradient,
    connectedGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1F8F5C), Color(0xFF156B44)],
    ),
    connectGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.primaryBright, AppColors.primary],
    ),
    shellBackground: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [AppColors.background, AppColors.backgroundWarm],
    ),
  );

  static const SecureWaveGradients dark = SecureWaveGradients(
    brandGradient: AppColors.brandGradient,
    connectedGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1F8F5C), Color(0xFF0D5A3A)],
    ),
    connectGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.primaryBright, AppColors.primaryDark],
    ),
    shellBackground: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [AppColors.darkBackground, AppColors.darkBackgroundWarm],
    ),
  );

  @override
  SecureWaveGradients copyWith({
    Gradient? brandGradient,
    Gradient? connectedGradient,
    Gradient? connectGradient,
    Gradient? shellBackground,
  }) {
    return SecureWaveGradients(
      brandGradient: brandGradient ?? this.brandGradient,
      connectedGradient: connectedGradient ?? this.connectedGradient,
      connectGradient: connectGradient ?? this.connectGradient,
      shellBackground: shellBackground ?? this.shellBackground,
    );
  }

  @override
  SecureWaveGradients lerp(
    covariant ThemeExtension<SecureWaveGradients>? other,
    double t,
  ) {
    if (other is! SecureWaveGradients) return this;
    return SecureWaveGradients(
      brandGradient:
          Gradient.lerp(brandGradient, other.brandGradient, t) ?? brandGradient,
      connectedGradient:
          Gradient.lerp(connectedGradient, other.connectedGradient, t) ??
              connectedGradient,
      connectGradient:
          Gradient.lerp(connectGradient, other.connectGradient, t) ??
              connectGradient,
      shellBackground:
          Gradient.lerp(shellBackground, other.shellBackground, t) ??
              shellBackground,
    );
  }
}

@immutable
class SecureWaveSemanticColors
    extends ThemeExtension<SecureWaveSemanticColors> {
  const SecureWaveSemanticColors({
    required this.success,
    required this.warning,
    required this.danger,
    required this.brand,
    required this.muted,
  });

  final Color success;
  final Color warning;
  final Color danger;
  final Color brand;
  final Color muted;

  static const SecureWaveSemanticColors light = SecureWaveSemanticColors(
    success: AppColors.success,
    warning: AppColors.warning,
    danger: AppColors.error,
    brand: AppColors.primary,
    muted: AppColors.inkSoft,
  );

  static const SecureWaveSemanticColors dark = SecureWaveSemanticColors(
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFFF6B6B),
    brand: AppColors.primaryBright,
    muted: AppColors.darkInkSoft,
  );

  @override
  SecureWaveSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? danger,
    Color? brand,
    Color? muted,
  }) {
    return SecureWaveSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      brand: brand ?? this.brand,
      muted: muted ?? this.muted,
    );
  }

  @override
  SecureWaveSemanticColors lerp(
    covariant ThemeExtension<SecureWaveSemanticColors>? other,
    double t,
  ) {
    if (other is! SecureWaveSemanticColors) return this;
    return SecureWaveSemanticColors(
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      brand: Color.lerp(brand, other.brand, t) ?? brand,
      muted: Color.lerp(muted, other.muted, t) ?? muted,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BuildContext Extension
// ─────────────────────────────────────────────────────────────────────────────

extension SecureWaveThemeContext on BuildContext {
  SecureWaveGradients get swGradients =>
      Theme.of(this).extension<SecureWaveGradients>() ??
      SecureWaveGradients.dark;

  SecureWaveSemanticColors get swColors =>
      Theme.of(this).extension<SecureWaveSemanticColors>() ??
      SecureWaveSemanticColors.dark;

  TextStyle get swCaption =>
      Theme.of(this).textTheme.bodySmall?.copyWith(
            color: Theme.of(this).colorScheme.onSurfaceVariant,
            letterSpacing: 0.3,
          ) ??
      const TextStyle();
}

// ─────────────────────────────────────────────────────────────────────────────
// SecureWaveTheme — entry point
// ─────────────────────────────────────────────────────────────────────────────

class SecureWaveTheme {
  SecureWaveTheme._();

  static ThemeMode get defaultThemeMode => ThemeMode.dark;

  static TextTheme _textTheme() {
    return GoogleFonts.plusJakartaSansTextTheme();
  }

  static ThemeData light() {
    final colorScheme = AppColors.lightScheme();
    final textTheme = _textTheme();

    final base = FlexThemeData.light(
      colorScheme: colorScheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
      blendLevel: 4,
      appBarStyle: FlexAppBarStyle.surface,
      appBarElevation: 0,
      bottomAppBarElevation: 0,
      tabBarStyle: FlexTabBarStyle.forAppBar,
      tooltipsMatchBackground: true,
      subThemesData: const FlexSubThemesData(
        interactionEffects: true,
        blendOnLevel: 8,
        blendOnColors: false,
        useM2StyleDividerInM3: false,
        defaultRadius: AppSpacing.radiusM,
        elevatedButtonSchemeColor: SchemeColor.primary,
        elevatedButtonSecondarySchemeColor: SchemeColor.onPrimary,
        inputDecoratorSchemeColor: SchemeColor.primary,
        inputDecoratorBackgroundAlpha: 12,
        inputDecoratorBorderType: FlexInputBorderType.outline,
        inputDecoratorRadius: AppSpacing.radiusM,
        inputDecoratorUnfocusedBorderIsColored: false,
        chipSchemeColor: SchemeColor.primaryContainer,
        chipRadius: AppSpacing.radiusFull,
        cardRadius: AppSpacing.radiusL,
        dialogRadius: AppSpacing.radiusXL,
        bottomSheetRadius: AppSpacing.radiusXL,
        navigationBarIndicatorSchemeColor: SchemeColor.primary,
        navigationBarIndicatorOpacity: 0.14,
        navigationRailIndicatorSchemeColor: SchemeColor.primary,
        navigationRailIndicatorOpacity: 0.14,
      ),
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      extensions: const <ThemeExtension<dynamic>>[
        SecureWaveGradients.light,
        SecureWaveSemanticColors.light,
      ],
    );
  }

  static ThemeData dark() {
    final colorScheme = AppColors.darkScheme();
    final textTheme = _textTheme();

    final base = FlexThemeData.dark(
      colorScheme: colorScheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
      blendLevel: 8,
      appBarStyle: FlexAppBarStyle.surface,
      appBarElevation: 0,
      bottomAppBarElevation: 0,
      tabBarStyle: FlexTabBarStyle.forAppBar,
      tooltipsMatchBackground: true,
      subThemesData: const FlexSubThemesData(
        interactionEffects: true,
        blendOnLevel: 12,
        blendOnColors: false,
        useM2StyleDividerInM3: false,
        defaultRadius: AppSpacing.radiusM,
        elevatedButtonSchemeColor: SchemeColor.primary,
        elevatedButtonSecondarySchemeColor: SchemeColor.onPrimary,
        inputDecoratorSchemeColor: SchemeColor.primary,
        inputDecoratorBackgroundAlpha: 20,
        inputDecoratorBorderType: FlexInputBorderType.outline,
        inputDecoratorRadius: AppSpacing.radiusM,
        inputDecoratorUnfocusedBorderIsColored: false,
        chipSchemeColor: SchemeColor.primaryContainer,
        chipRadius: AppSpacing.radiusFull,
        cardRadius: AppSpacing.radiusL,
        dialogRadius: AppSpacing.radiusXL,
        bottomSheetRadius: AppSpacing.radiusXL,
        navigationBarIndicatorSchemeColor: SchemeColor.primary,
        navigationBarIndicatorOpacity: 0.18,
        navigationRailIndicatorSchemeColor: SchemeColor.primary,
        navigationRailIndicatorOpacity: 0.18,
      ),
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.darkBackground,
      extensions: const <ThemeExtension<dynamic>>[
        SecureWaveGradients.dark,
        SecureWaveSemanticColors.dark,
      ],
    );
  }
}

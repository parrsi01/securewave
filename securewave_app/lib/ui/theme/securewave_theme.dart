import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'securewave_palette.dart';

class SecureWaveTheme {
  SecureWaveTheme._();

  static const ThemeMode defaultThemeMode = ThemeMode.dark;

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final flexColors = FlexSchemeColor.from(
      brightness: brightness,
      primary: SecureWavePalette.brand,
      primaryContainer:
          isDark ? const Color(0xFF12353F) : const Color(0xFFD7F0EC),
      secondary: isDark ? SecureWavePalette.mint : SecureWavePalette.brandMid,
      secondaryContainer:
          isDark ? const Color(0xFF163842) : const Color(0xFFE6F1F0),
      tertiary:
          isDark ? SecureWavePalette.graphUpload : SecureWavePalette.graphDownload,
      tertiaryContainer:
          isDark ? const Color(0xFF163348) : const Color(0xFFDCE8F5),
      appBarColor: isDark ? SecureWavePalette.darkBgAlt : Colors.white,
      error: SecureWavePalette.danger,
      errorContainer:
          isDark ? const Color(0xFF4B2321) : const Color(0xFFFFDDD8),
    );

    final base = isDark
        ? FlexThemeData.dark(
            colors: flexColors,
            useMaterial3: true,
            surfaceMode: FlexSurfaceMode.highBackgroundLowScaffold,
            blendLevel: 6,
            subThemesData: const FlexSubThemesData(
              defaultRadius: SecureWaveRadius.xl,
              blendOnLevel: 0,
              navigationBarLabelBehavior:
                  NavigationDestinationLabelBehavior.alwaysShow,
              inputDecoratorBorderType: FlexInputBorderType.outline,
            ),
          )
        : FlexThemeData.light(
            colors: flexColors,
            useMaterial3: true,
            surfaceMode: FlexSurfaceMode.highBackgroundLowScaffold,
            blendLevel: 4,
            subThemesData: const FlexSubThemesData(
              defaultRadius: SecureWaveRadius.xl,
              blendOnLevel: 0,
              navigationBarLabelBehavior:
                  NavigationDestinationLabelBehavior.alwaysShow,
              inputDecoratorBorderType: FlexInputBorderType.outline,
            ),
          );

    final scheme = base.colorScheme.copyWith(
      primary: isDark ? const Color(0xFF6FD6CD) : SecureWavePalette.brand,
      onPrimary: isDark ? SecureWavePalette.brandDeep : Colors.white,
      primaryContainer:
          isDark ? const Color(0xFF12353F) : const Color(0xFFD7F0EC),
      secondary: isDark ? const Color(0xFF8AE0DA) : SecureWavePalette.brandMid,
      tertiary: isDark
          ? SecureWavePalette.graphUpload
          : SecureWavePalette.graphDownload,
      surface:
          isDark ? SecureWavePalette.darkSurface : SecureWavePalette.lightSurface,
      surfaceContainerHighest: isDark
          ? SecureWavePalette.darkSurfaceMuted
          : SecureWavePalette.lightSurfaceMuted,
      onSurface:
          isDark ? SecureWavePalette.darkInk : SecureWavePalette.lightInk,
      outline:
          isDark ? SecureWavePalette.darkBorder : SecureWavePalette.lightBorder,
      error: SecureWavePalette.danger,
      onError: Colors.white,
    );

    final semanticColors = SecureWaveSemanticColors(
      primary: scheme.primary,
      primaryContainer: scheme.primaryContainer,
      connectionActive: SecureWavePalette.success,
      connectionInactive:
          isDark ? const Color(0xFF607983) : const Color(0xFF8EA5AD),
      connectionError: SecureWavePalette.danger,
      surfaceElevated:
          isDark ? const Color(0xFF162931) : const Color(0xFFF8FBFB),
    );

    final body = GoogleFonts.plusJakartaSansTextTheme(base.textTheme);
    final textTheme = body.copyWith(
      displayLarge: body.displayLarge?.copyWith(
        fontSize: 44,
        height: 1.04,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.4,
        color: scheme.onSurface,
      ),
      titleLarge: body.titleLarge?.copyWith(
        fontSize: 24,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.35,
        color: scheme.onSurface,
      ),
      titleMedium: body.titleMedium?.copyWith(
        fontSize: 18,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.15,
        color: scheme.onSurface,
      ),
      bodyLarge: body.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      bodyMedium: body.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w500,
        color:
            isDark ? SecureWavePalette.darkMuted : SecureWavePalette.lightMuted,
      ),
      bodySmall: body.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.35,
        fontWeight: FontWeight.w500,
        color:
            isDark ? SecureWavePalette.darkMuted : SecureWavePalette.lightMuted,
      ),
      labelLarge: body.labelLarge?.copyWith(
        fontSize: 14,
        height: 1.1,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.15,
        color: scheme.onSurface,
      ),
      labelMedium: body.labelMedium?.copyWith(
        fontSize: 13,
        height: 1.1,
        fontWeight: FontWeight.w600,
        color:
            isDark ? SecureWavePalette.darkMuted : SecureWavePalette.lightMuted,
      ),
      labelSmall: body.labelSmall?.copyWith(
        fontSize: 12,
        height: 1.1,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.12,
        color:
            isDark ? SecureWavePalette.darkMuted : SecureWavePalette.lightMuted,
      ),
    );

    final outline =
        scheme.outline.withValues(alpha: isDark ? 0.72 : 0.42);

    return base.copyWith(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isDark ? SecureWavePalette.darkBg : SecureWavePalette.lightBg,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[
        SecureWaveGradients(
          canvas: isDark
              ? SecureWavePalette.shellBackgroundDark
              : SecureWavePalette.shellBackgroundLight,
          panel: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? <Color>[
                    semanticColors.surfaceElevated.withValues(alpha: 0.98),
                    SecureWavePalette.darkSurface.withValues(alpha: 0.98),
                  ]
                : <Color>[
                    Colors.white.withValues(alpha: 0.98),
                    semanticColors.surfaceElevated.withValues(alpha: 0.98),
                  ],
          ),
          accent: isDark
              ? SecureWavePalette.connectGradient
              : SecureWavePalette.brandGradient,
          active: SecureWavePalette.connectedGradient,
        ),
        semanticColors,
      ],
      dividerColor: outline,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: semanticColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SecureWaveRadius.xl),
          side: BorderSide(color: outline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: semanticColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SecureWaveRadius.xl),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 78,
        backgroundColor:
            semanticColors.surfaceElevated.withValues(alpha: isDark ? 0.96 : 0.98),
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.18 : 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            color: selected ? scheme.primary : textTheme.bodySmall?.color,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : textTheme.bodySmall?.color,
            size: 22,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        selectedIconTheme: IconThemeData(color: scheme.primary, size: 22),
        unselectedIconTheme: IconThemeData(
          color: textTheme.bodySmall?.color,
          size: 22,
        ),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.primary,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.18 : 0.1),
        groupAlignment: -0.4,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: semanticColors.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SecureWaveSpacing.spaceSM,
          vertical: SecureWaveSpacing.spaceSM,
        ),
        hintStyle: textTheme.bodyMedium,
        labelStyle: textTheme.bodyMedium,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SecureWaveRadius.lg),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SecureWaveRadius.lg),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SecureWaveRadius.lg),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: scheme.onPrimary,
          backgroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(
            horizontal: SecureWaveSpacing.spaceSM,
            vertical: SecureWaveSpacing.spaceSM,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SecureWaveRadius.lg),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: outline),
          padding: const EdgeInsets.symmetric(
            horizontal: SecureWaveSpacing.spaceSM,
            vertical: SecureWaveSpacing.spaceSM,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SecureWaveRadius.lg),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: semanticColors.surfaceElevated,
        side: BorderSide(color: outline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SecureWaveRadius.pill),
        ),
        labelStyle: textTheme.labelMedium,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.primary.withValues(alpha: isDark ? 0.14 : 0.12);
            }
            return semanticColors.surfaceElevated;
          }),
          side: WidgetStateProperty.all(BorderSide(color: outline)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SecureWaveRadius.lg),
            ),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.primary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SecureWaveSpacing.spaceXS,
          vertical: SecureWaveSpacing.spaceXS,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SecureWaveRadius.lg),
        ),
      ),
    );
  }
}

class SecureWaveSpacing {
  SecureWaveSpacing._();

  static const double spaceXS = 8;
  static const double spaceSM = 16;
  static const double spaceMD = 24;
  static const double spaceLG = 32;
  static const double spaceXL = 48;

  static const double xs = spaceXS;
  static const double sm = spaceSM;
  static const double md = spaceMD;
  static const double lg = spaceLG;
  static const double xl = spaceXL;
  static const double xxl = 56;
  static const double xxxl = 72;
}

class SecureWaveRadius {
  SecureWaveRadius._();

  static const double md = 18;
  static const double lg = 24;
  static const double xl = 32;
  static const double pill = 999;
}

class SecureWaveBreakpoints {
  SecureWaveBreakpoints._();

  static const double compact = 760;
  static const double medium = 1120;
  static const double expanded = 1400;
}

@immutable
class SecureWaveGradients extends ThemeExtension<SecureWaveGradients> {
  const SecureWaveGradients({
    required this.canvas,
    required this.panel,
    required this.accent,
    required this.active,
  });

  final Gradient canvas;
  final Gradient panel;
  final Gradient accent;
  final Gradient active;

  @override
  SecureWaveGradients copyWith({
    Gradient? canvas,
    Gradient? panel,
    Gradient? accent,
    Gradient? active,
  }) {
    return SecureWaveGradients(
      canvas: canvas ?? this.canvas,
      panel: panel ?? this.panel,
      accent: accent ?? this.accent,
      active: active ?? this.active,
    );
  }

  @override
  SecureWaveGradients lerp(
    ThemeExtension<SecureWaveGradients>? other,
    double t,
  ) {
    if (other is! SecureWaveGradients) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}

@immutable
class SecureWaveSemanticColors extends ThemeExtension<SecureWaveSemanticColors> {
  const SecureWaveSemanticColors({
    required this.primary,
    required this.primaryContainer,
    required this.connectionActive,
    required this.connectionInactive,
    required this.connectionError,
    required this.surfaceElevated,
  });

  final Color primary;
  final Color primaryContainer;
  final Color connectionActive;
  final Color connectionInactive;
  final Color connectionError;
  final Color surfaceElevated;

  @override
  SecureWaveSemanticColors copyWith({
    Color? primary,
    Color? primaryContainer,
    Color? connectionActive,
    Color? connectionInactive,
    Color? connectionError,
    Color? surfaceElevated,
  }) {
    return SecureWaveSemanticColors(
      primary: primary ?? this.primary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      connectionActive: connectionActive ?? this.connectionActive,
      connectionInactive: connectionInactive ?? this.connectionInactive,
      connectionError: connectionError ?? this.connectionError,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
    );
  }

  @override
  SecureWaveSemanticColors lerp(
    ThemeExtension<SecureWaveSemanticColors>? other,
    double t,
  ) {
    if (other is! SecureWaveSemanticColors) {
      return this;
    }
    return SecureWaveSemanticColors(
      primary: Color.lerp(primary, other.primary, t) ?? primary,
      primaryContainer:
          Color.lerp(primaryContainer, other.primaryContainer, t) ??
              primaryContainer,
      connectionActive:
          Color.lerp(connectionActive, other.connectionActive, t) ??
              connectionActive,
      connectionInactive:
          Color.lerp(connectionInactive, other.connectionInactive, t) ??
              connectionInactive,
      connectionError:
          Color.lerp(connectionError, other.connectionError, t) ??
              connectionError,
      surfaceElevated:
          Color.lerp(surfaceElevated, other.surfaceElevated, t) ??
              surfaceElevated,
    );
  }
}

extension SecureWaveThemeContext on BuildContext {
  SecureWaveGradients get swGradients {
    final theme = Theme.of(this);
    return theme.extension<SecureWaveGradients>() ??
        SecureWaveGradients(
          canvas: theme.brightness == Brightness.dark
              ? SecureWavePalette.shellBackgroundDark
              : SecureWavePalette.shellBackgroundLight,
          panel: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: theme.brightness == Brightness.dark
                ? <Color>[
                    SecureWavePalette.darkSurfaceMuted.withValues(alpha: 0.98),
                    SecureWavePalette.darkSurface.withValues(alpha: 0.98),
                  ]
                : <Color>[
                    Colors.white.withValues(alpha: 0.98),
                    SecureWavePalette.lightSurfaceMuted.withValues(alpha: 0.98),
                  ],
          ),
          accent: theme.brightness == Brightness.dark
              ? SecureWavePalette.connectGradient
              : SecureWavePalette.brandGradient,
          active: SecureWavePalette.connectedGradient,
        );
  }

  SecureWaveSemanticColors get swColors {
    final theme = Theme.of(this);
    return theme.extension<SecureWaveSemanticColors>() ??
        SecureWaveSemanticColors(
          primary: theme.colorScheme.primary,
          primaryContainer: theme.colorScheme.primaryContainer,
          connectionActive: SecureWavePalette.success,
          connectionInactive: theme.brightness == Brightness.dark
              ? const Color(0xFF607983)
              : const Color(0xFF8EA5AD),
          connectionError: SecureWavePalette.danger,
          surfaceElevated: theme.brightness == Brightness.dark
              ? const Color(0xFF162931)
              : const Color(0xFFF8FBFB),
        );
  }

  TextStyle? get swCaption => Theme.of(this).textTheme.labelSmall;
}

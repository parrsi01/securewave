import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'typography.dart';

class SecureWaveTheme {
  const SecureWaveTheme._();

  static ThemeData dark() {
    final base = FlexThemeData.dark(
      scheme: FlexScheme.deepBlue,
      useMaterial3: true,
      blendLevel: 18,
      appBarElevation: 0,
      scaffoldBackground: SecureWaveTokens.background,
      colors: const FlexSchemeColor(
        primary: SecureWaveTokens.accent,
        primaryContainer: SecureWaveTokens.surfaceMuted,
        secondary: SecureWaveTokens.accentSun,
        secondaryContainer: Color(0xFF553F0D),
        tertiary: SecureWaveTokens.success,
        tertiaryContainer: Color(0xFF0F4731),
        appBarColor: SecureWaveTokens.background,
        error: SecureWaveTokens.danger,
      ),
      textTheme: SecureWaveTypography.textTheme(Brightness.dark),
      subThemesData: const FlexSubThemesData(
        interactionEffects: true,
        defaultRadius: SecureWaveTokens.radiusMd,
        cardRadius: SecureWaveTokens.radiusLg,
        inputDecoratorRadius: SecureWaveTokens.radiusMd,
        inputDecoratorBorderType: FlexInputBorderType.outline,
        navigationBarIndicatorRadius: SecureWaveTokens.radiusMd,
        outlinedButtonRadius: 999,
        elevatedButtonRadius: 999,
        filledButtonRadius: 999,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      dividerColor: SecureWaveTokens.border,
      cardColor: SecureWaveTokens.surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: SecureWaveTokens.ink,
      ),
      iconTheme: const IconThemeData(color: SecureWaveTokens.ink),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: SecureWaveTokens.surfaceMuted,
        hintStyle: const TextStyle(color: SecureWaveTokens.inkSoft),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: SecureWaveTokens.ink,
        displayColor: SecureWaveTokens.ink,
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: SecureWaveTokens.backgroundStrong,
        indicatorColor: SecureWaveTokens.accentSoft,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: SecureWaveTokens.surfaceMuted,
        selectedColor: SecureWaveTokens.accentSoft,
        side: const BorderSide(color: SecureWaveTokens.border),
        labelStyle: base.textTheme.bodySmall?.copyWith(
          color: SecureWaveTokens.inkMuted,
        ),
      ),
    );
  }
}

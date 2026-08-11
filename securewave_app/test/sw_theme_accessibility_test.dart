import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securewave_app/ui/sw_theme.dart';

void main() {
  test('small-text token pairs meet WCAG AA contrast', () {
    expect(
      _contrast(SwColors.textSecondary, SwColors.background),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(SwColors.textSecondary, SwColors.surfaceSecondary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(SwColors.primaryStrong, SwColors.primarySoft),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('shared small labels remain readable', () {
    expect(SwType.micro.fontSize, greaterThanOrEqualTo(11));
    expect(SwType.label.fontSize, greaterThanOrEqualTo(12));
    expect(SwType.footnote.fontSize, greaterThanOrEqualTo(12));
  });
}

double _contrast(Color foreground, Color background) {
  final lighter = math.max(_luminance(foreground), _luminance(background));
  final darker = math.min(_luminance(foreground), _luminance(background));
  return (lighter + 0.05) / (darker + 0.05);
}

double _luminance(Color color) {
  final argb = color.toARGB32();
  final red = (argb >> 16) & 0xff;
  final green = (argb >> 8) & 0xff;
  final blue = argb & 0xff;
  return 0.2126 * _linear(red) +
      0.7152 * _linear(green) +
      0.0722 * _linear(blue);
}

double _linear(int channel) {
  final value = channel / 255;
  return value <= 0.04045
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
}

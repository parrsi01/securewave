import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// SecureWave SVG logo mark.
///
/// Loads the brand logo from assets. Use [size] to control both width and
/// height (square bounding box). The SVG scales proportionally within.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 48,
    this.color,
  });

  /// Bounding box dimension (width & height).
  final double size;

  /// Optional color override applied via [ColorFilter].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/securewave_logo.svg',
      width: size,
      height: size,
      colorFilter: color != null
          ? ColorFilter.mode(color!, BlendMode.srcIn)
          : null,
    );
  }
}

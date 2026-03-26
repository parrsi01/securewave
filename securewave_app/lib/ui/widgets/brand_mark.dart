import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart' as htb;

/// SecureWave brand mark.
///
/// Uses the shared SVG shield asset and can optionally render the wordmark.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 44,
    this.showText = true,
    this.textSize = 20,
    this.textColor,
    this.accentColor,
  });

  final double size;
  final bool showText;
  final double textSize;
  final Color? textColor;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final logo = SvgPicture.asset(
      'assets/securewave_logo.svg',
      width: size,
      height: size,
    );

    if (!showText) {
      return logo;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        const SizedBox(width: 12),
        Flexible(
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                textColor ?? htb.HtbColors.accentSecondary,
                accentColor ?? htb.HtbColors.accentSecondaryMuted,
                htb.HtbColors.accentPrimary,
              ],
            ).createShader(bounds),
            child: Text(
              'SecureWave',
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                color: htb.HtbColors.textPrimary,
                fontSize: textSize,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

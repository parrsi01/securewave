import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 44,
    this.showWordmark = true,
  });

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SvgPicture.asset(
          'assets/securewave_logo.svg',
          width: size,
          height: size,
        ),
        if (showWordmark) ...<Widget>[
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'SecureWave',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
              ),
              Text(
                'Private network orchestration',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      letterSpacing: 0.2,
                    ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

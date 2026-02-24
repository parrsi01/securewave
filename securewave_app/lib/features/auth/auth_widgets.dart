import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';

/// Shared widgets for auth screens (login + register).

class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.headline, required this.subline});
  final String headline;
  final String subline;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppColors.authHeaderGradient),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space5,
        AppSpacing.space6,
        AppSpacing.space5,
        AppSpacing.space6,
      ),
      child: Column(
        children: [
          Hero(
            tag: 'securewave_logo',
            child: SvgPicture.asset(
              'assets/securewave_logo.svg',
              width: 52,
              height: 52,
            ),
          ),
          const SizedBox(height: AppSpacing.space4),
          Text(
            headline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            subline,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class AuthFieldLabel extends StatelessWidget {
  const AuthFieldLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space3,
      ),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: AppSpacing.iconXS, color: AppColors.error),
          const SizedBox(width: AppSpacing.space2),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

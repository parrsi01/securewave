import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../ui/design/app_spacing.dart';
import '../../ui/theme/app_colors.dart' as htb;

/// Shared widgets for auth screens (login + register).

class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.headline, required this.subline});
  final String headline;
  final String subline;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final logoSize = (width * 0.14).clamp(44.0, 64.0).toDouble();
        final headlineSize = (width * 0.07).clamp(22.0, 30.0).toDouble();
        final sublineSize = (width * 0.038).clamp(13.0, 15.0).toDouble();

        return Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [htb.HtbColors.bg2, htb.HtbColors.bg3],
            ),
            border: Border(
              bottom: BorderSide(
                color: htb.HtbColors.glassBorderDefault,
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: htb.HtbColors.glowCyan,
                blurRadius: 26,
                offset: Offset(0, 8),
              ),
            ],
          ),
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
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.space3),
                  decoration: BoxDecoration(
                    color: htb.HtbColors.neonCyanGhost,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
                    border: Border.all(
                      color: htb.HtbColors.glassBorderDefault,
                    ),
                  ),
                  child: SvgPicture.asset(
                    'assets/securewave_logo.svg',
                    width: logoSize,
                    height: logoSize,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space4),
              Text(
                headline,
                style: TextStyle(
                  color: htb.HtbColors.textPrimary,
                  fontSize: headlineSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.space1),
              Text(
                subline,
                style: TextStyle(
                  color: htb.HtbColors.textSecondary,
                  fontSize: sublineSize,
                  fontWeight: FontWeight.w400,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
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
        color: const Color(0x14FF7272),
        border: Border.all(color: const Color(0x33FF7272)),
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: AppSpacing.iconXS, color: htb.HtbColors.statusDisconnected),
          const SizedBox(width: AppSpacing.space2),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: htb.HtbColors.statusDisconnected,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

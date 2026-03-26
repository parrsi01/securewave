import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/app_theme.dart';
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
            gradient: AppColors.authHeaderGradient,
            border: Border(
              bottom: BorderSide(
                color: htb.HtbColors.glassBorderDefault,
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: htb.HtbColors.glowSecondary,
                blurRadius: 30,
                offset: Offset(0, 12),
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
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
                    border: Border.all(
                      color: htb.HtbColors.glassBorderDefault,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: htb.HtbColors.glowSecondary,
                        blurRadius: 22,
                        offset: Offset(0, 10),
                      ),
                    ],
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
      decoration: AppTheme.authErrorDecoration(),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: AppSpacing.iconXS,
            color: htb.HtbColors.statusDisconnected,
          ),
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

class AuthFeaturePanel extends StatelessWidget {
  const AuthFeaturePanel({
    super.key,
    required this.kicker,
    required this.title,
    required this.description,
    required this.items,
  });

  final String kicker;
  final String title;
  final String description;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            htb.HtbColors.accentSecondaryGhost,
            htb.HtbColors.accentPrimaryGhost,
          ],
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
        border: Border.all(color: htb.HtbColors.glassBorderDefault),
        boxShadow: const [
          BoxShadow(
            color: htb.HtbColors.glowSecondary,
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kicker,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: htb.HtbColors.textMono,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: htb.HtbColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: htb.HtbColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.space4),
          for (final item in items) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: const BoxDecoration(
                    color: htb.HtbColors.accentSecondary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: htb.HtbColors.glowSecondary,
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.space3),
                Expanded(
                  child: Text(
                    item,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: htb.HtbColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),
            if (item != items.last) const SizedBox(height: AppSpacing.space3),
          ],
        ],
      ),
    );
  }
}

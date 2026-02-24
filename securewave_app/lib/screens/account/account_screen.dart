import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/user_plan.dart';
import '../../core/services/auth_session.dart';
import '../../core/state/app_state.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';

/// Account screen — v2.
///
/// Gradient header with floating avatar, modern plan badge,
/// redesigned usage gauge, and sleek upgrade CTA.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final auth     = ref.watch(authSessionProvider);
    final planAsync = ref.watch(userPlanProvider);
    final email    = auth.email ?? 'Not signed in';
    final initial  = email.isNotEmpty ? email[0].toUpperCase() : '?';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ── Gradient header ──────────────────────────────────────────
            _GradientHeader(
              initial: initial,
              email: email,
              planAsync: planAsync,
            ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.space5),
              child: Column(
                children: [
                  // ── Usage gauge ────────────────────────────────────────
                  planAsync.when(
                    data: (plan) => plan.isUnlimited
                        ? _UnlimitedBadge(isDark: isDark)
                        : _UsageGauge(plan: plan, isDark: isDark),
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.space6),
                      child: Center(
                          child: CircularProgressIndicator(strokeCap: StrokeCap.round)),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),

                  const SizedBox(height: AppSpacing.space5),

                  // ── Upgrade / Manage CTA ───────────────────────────────
                  planAsync.when(
                    data: (plan) => plan.isPremium
                        ? _ManagePlanButton(isDark: isDark)
                        : _UpgradeButton(isDark: isDark),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),

                  const SizedBox(height: AppSpacing.space8),

                  // ── Sign out ───────────────────────────────────────────
                  OutlinedButton.icon(
                    onPressed: () => _confirmSignOut(context, ref),
                    icon: const Icon(Icons.logout_rounded, size: AppSpacing.iconXS),
                    label: const Text('Sign Out'),
                  ),

                  const SizedBox(height: AppSpacing.space4),
                  Text(
                    'SecureWave v4.0.0',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.space4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authSessionProvider).clearSession();
              context.go('/login');
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}

// ── Gradient header ─────────────────────────────────────────────────────────

class _GradientHeader extends StatelessWidget {
  const _GradientHeader({
    required this.initial,
    required this.email,
    required this.planAsync,
  });

  final String initial;
  final String email;
  final AsyncValue<UserPlan> planAsync;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.authHeaderGradient),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space5,
        AppSpacing.space8,
        AppSpacing.space5,
        AppSpacing.space8,
      ),
      child: Column(
        children: [
          // Avatar
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 44,
              backgroundColor: AppColors.primaryBright,
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space3),

          // Email
          Text(
            email,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: AppSpacing.space2),

          // Plan badge
          planAsync.whenOrNull(
            data: (plan) => Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space3,
                vertical: AppSpacing.space1,
              ),
              decoration: BoxDecoration(
                color: plan.isPremium
                    ? AppColors.secondary
                    : Colors.white.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
              child: Text(
                plan.name.toUpperCase(),
                style: TextStyle(
                  color: plan.isPremium ? AppColors.ink : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ) ?? const SizedBox.shrink(),
        ],
      ),
    );
  }
}

// ── Unlimited badge ─────────────────────────────────────────────────────────

class _UnlimitedBadge extends StatelessWidget {
  const _UnlimitedBadge({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXXL),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.all_inclusive_rounded, size: 52,
              color: isDark ? AppColors.primaryBright : AppColors.primary),
          const SizedBox(height: AppSpacing.space3),
          Text('Unlimited Data',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.space1),
          Text('No usage restrictions on your plan.',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ── Usage gauge ─────────────────────────────────────────────────────────────

class _UsageGauge extends StatelessWidget {
  const _UsageGauge({required this.plan, required this.isDark});
  final UserPlan plan;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXXL),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 160,
            height: 160,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: plan.usagePercent),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                final gaugeColor = value < 0.8
                    ? (isDark ? AppColors.primaryBright : AppColors.primary)
                    : value < 0.95
                        ? AppColors.warning
                        : AppColors.error;
                return CustomPaint(
                  painter: _GaugePainter(
                      value: value, color: gaugeColor, isDark: isDark),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${plan.usedGb.toStringAsFixed(1)} GB',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'of ${plan.dataCapGb.toStringAsFixed(0)} GB',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.space3),
          Text(
            '${plan.remainingGb.toStringAsFixed(1)} GB remaining',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ── Upgrade button ──────────────────────────────────────────────────────────

class _UpgradeButton extends StatelessWidget {
  const _UpgradeButton({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upgrades managed via web portal')),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
              SizedBox(width: AppSpacing.space2),
              Text(
                'Upgrade to Premium',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Manage plan button ──────────────────────────────────────────────────────

class _ManagePlanButton extends StatelessWidget {
  const _ManagePlanButton({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Manage via web portal')),
        ),
        icon: const Icon(Icons.settings_outlined, size: AppSpacing.iconXS),
        label: const Text('Manage Plan'),
      ),
    );
  }
}

// ── Gauge painter ───────────────────────────────────────────────────────────

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value, required this.color, required this.isDark});
  final double value;
  final Color color;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 14;
    const startAngle = 145 * math.pi / 180;
    const sweepTotal = 250 * math.pi / 180;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final trackColor = isDark ? AppColors.darkBorder : AppColors.border;

    // Track
    canvas.drawArc(
      rect, startAngle, sweepTotal, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..color = trackColor,
    );

    // Fill arc
    if (value > 0) {
      canvas.drawArc(
        rect, startAngle, sweepTotal * value.clamp(0, 1), false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: startAngle,
            endAngle: startAngle + sweepTotal,
            colors: [color.withValues(alpha: 0.6), color],
            transform: const GradientRotation(0),
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      value != old.value || color != old.color || isDark != old.isDark;
}

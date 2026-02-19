import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/auth_session.dart';
import '../../core/state/app_state.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    final planAsync = ref.watch(userPlanProvider);
    final email = auth.email ?? 'Not signed in';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.space5),
          children: [
            const SizedBox(height: AppSpacing.space5),
            // Avatar
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.primaryLight,
                child: Text(initial, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
            Center(child: Text(email, style: Theme.of(context).textTheme.bodyLarge)),
            const SizedBox(height: AppSpacing.space2),

            // Plan badge
            planAsync.when(
              data: (plan) {
                final badgeColor = plan.isPremium ? AppColors.primary : AppColors.surfaceMuted;
                final textColor = plan.isPremium ? Colors.white : AppColors.ink;
                return Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space1),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                    ),
                    child: Text(plan.name, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.space6),

            // Usage gauge
            planAsync.when(
              data: (plan) {
                if (plan.isUnlimited) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.space5),
                      child: Column(
                        children: [
                          Icon(Icons.all_inclusive_rounded, size: 48, color: AppColors.primary),
                          const SizedBox(height: AppSpacing.space3),
                          Text('Unlimited Data', style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                    ),
                  );
                }
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.space5),
                    child: Column(
                      children: [
                        SizedBox(
                          width: 160,
                          height: 160,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: plan.usagePercent),
                            duration: const Duration(milliseconds: 800),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, _) {
                              final gaugeColor = value < 0.8
                                  ? AppColors.primary
                                  : value < 0.95
                                      ? AppColors.warning
                                      : AppColors.error;
                              return CustomPaint(
                                painter: _GaugePainter(value: value, color: gaugeColor),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('${plan.usedGb.toStringAsFixed(1)} GB', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                                      Text('of ${plan.dataCapGb.toStringAsFixed(0)} GB', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkMuted)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: AppSpacing.space3),
                        Text('${plan.remainingGb.toStringAsFixed(1)} GB remaining', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkMuted)),
                      ],
                    ),
                  ),
                );
              },
              loading: () => const Card(child: Padding(padding: EdgeInsets.all(AppSpacing.space8), child: Center(child: CircularProgressIndicator()))),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.space4),

            // Upgrade button
            planAsync.when(
              data: (plan) {
                if (plan.isPremium) {
                  return OutlinedButton.icon(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Manage via web portal'))),
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Manage Plan'),
                  );
                }
                return Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upgrades managed via web portal'))),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.bolt_rounded, color: Colors.white),
                          SizedBox(width: AppSpacing.space2),
                          Text('Upgrade to Premium', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.space8),

            // Sign out
            Center(
              child: OutlinedButton.icon(
                onPressed: () => showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sign Out'),
                    content: const Text('Are you sure you want to sign out?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
                ),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign Out'),
              ),
            ),
            const SizedBox(height: AppSpacing.space4),
            Center(child: Text('SecureWave v4.0.0', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft))),
            const SizedBox(height: AppSpacing.space4),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    const startAngle = 150 * math.pi / 180;
    const sweepTotal = 240 * math.pi / 180;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background arc
    canvas.drawArc(
      rect, startAngle, sweepTotal, false,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 10..strokeCap = StrokeCap.round..color = AppColors.border,
    );

    // Filled arc
    canvas.drawArc(
      rect, startAngle, sweepTotal * value.clamp(0, 1), false,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 10..strokeCap = StrokeCap.round..color = color,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) => value != old.value || color != old.color;
}

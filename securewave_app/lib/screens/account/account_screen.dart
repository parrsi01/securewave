import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/user_plan.dart';
import '../../core/services/device_identity.dart';
import '../../core/services/auth_session.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../debug/automation_keys.dart';
import '../../services/api_client.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = ref.watch(authSessionProvider);
    final planAsync = ref.watch(userPlanProvider);
    final sessionUsageBytes =
        ref.watch(vpnStateProvider.select((s) => s.sessionTransferredBytes));
    final lifetimeUsageBytes =
        ref.watch(vpnStateProvider.select((s) => s.lifetimeTransferredBytes));
    final email = auth.email ?? 'Not signed in';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';

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
                  const _DeviceOverviewCard(),
                  const SizedBox(height: AppSpacing.space5),
                  // ── Usage gauge ────────────────────────────────────────
                  planAsync.when(
                    data: (plan) => plan.isUnlimited
                        ? _UnlimitedBadge(isDark: isDark)
                        : _UsageGauge(
                            plan: plan,
                            isDark: isDark,
                            sessionUsageBytes: sessionUsageBytes,
                            lifetimeUsageBytes: lifetimeUsageBytes,
                          ),
                    loading: () => const Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: AppSpacing.space6),
                      child: Center(
                          child: CircularProgressIndicator(
                              strokeCap: StrokeCap.round)),
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

                  const SizedBox(height: AppSpacing.space4),

                  // ── Edit Profile ─────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/edit-profile'),
                      icon: const Icon(Icons.edit_outlined,
                          size: AppSpacing.iconXS),
                      label: const Text('Edit Profile'),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.space4),

                  // ── Sign out ───────────────────────────────────────────
                  OutlinedButton.icon(
                    key: const ValueKey<String>(
                      AutomationKeys.accountSignOutButton,
                    ),
                    onPressed: () => _confirmSignOut(context, ref),
                    icon: const Icon(Icons.logout_rounded,
                        size: AppSpacing.iconXS),
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
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            key: const ValueKey<String>(
              AutomationKeys.accountConfirmSignOutButton,
            ),
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

String _formatUsageAmount(int bytes) {
  const kb = 1024.0;
  const mb = kb * 1024.0;
  const gb = mb * 1024.0;
  if (bytes <= 0) return '0 MB';
  if (bytes >= gb) {
    final value = bytes / gb;
    return '${value.toStringAsFixed(value < 10 ? 2 : 1)} GB';
  }
  if (bytes >= mb) {
    final value = bytes / mb;
    return '${value.toStringAsFixed(value < 10 ? 1 : 0)} MB';
  }
  final value = bytes / kb;
  return '${value.toStringAsFixed(value < 10 ? 1 : 0)} KB';
}

String _formatUsagePercent(double progress) {
  final percent = (progress * 100).clamp(0.0, 100.0);
  if (percent <= 0) return '0%';
  if (percent < 1) return '${percent.toStringAsFixed(2)}%';
  if (percent < 10) return '${percent.toStringAsFixed(1)}%';
  return '${percent.toStringAsFixed(0)}%';
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
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3), width: 3),
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
              ) ??
              const SizedBox.shrink(),
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
          Icon(Icons.all_inclusive_rounded,
              size: 52,
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
  const _UsageGauge({
    required this.plan,
    required this.isDark,
    required this.sessionUsageBytes,
    required this.lifetimeUsageBytes,
  });
  final UserPlan plan;
  final bool isDark;
  final int sessionUsageBytes;
  final int lifetimeUsageBytes;

  @override
  Widget build(BuildContext context) {
    final effectiveUsedBytes = (plan.usedBytes + sessionUsageBytes)
        .clamp(0, plan.dataCapBytes)
        .toInt();
    final progress = plan.dataCapBytes <= 0
        ? 0.0
        : (effectiveUsedBytes / plan.dataCapBytes).clamp(0.0, 1.0).toDouble();
    final effectiveRemainingBytes =
        (plan.dataCapBytes - effectiveUsedBytes).clamp(0, plan.dataCapBytes);
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_formatUsageAmount(effectiveUsedBytes)} used of '
            '${_formatUsageAmount(plan.dataCapBytes)}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            '${_formatUsagePercent(progress)} used',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.space4),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              final gaugeColor = value < 0.7
                  ? (isDark ? AppColors.primaryBright : AppColors.primary)
                  : value <= 0.9
                      ? AppColors.warning
                      : AppColors.error;
              return ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                child: SizedBox(
                  height: 12,
                  child: LinearProgressIndicator(
                    value: value,
                    backgroundColor:
                        isDark ? AppColors.darkBorder : AppColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(gaugeColor),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.space3),
          Text(
            '${_formatUsageAmount(effectiveRemainingBytes)} remaining',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? AppColors.darkInkMuted : AppColors.inkMuted,
                ),
          ),
          if (sessionUsageBytes > 0) ...[
            const SizedBox(height: AppSpacing.space2),
            Text(
              'Current session: ${_formatUsageAmount(sessionUsageBytes)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark ? AppColors.darkInkSoft : AppColors.inkMuted,
                  ),
            ),
          ],
          if (lifetimeUsageBytes > 0) ...[
            const SizedBox(height: AppSpacing.space1),
            Text(
              'This device total: ${_formatUsageAmount(lifetimeUsageBytes)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark ? AppColors.darkInkSoft : AppColors.inkMuted,
                  ),
            ),
          ],
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

class _DeviceOverviewCard extends ConsumerStatefulWidget {
  const _DeviceOverviewCard();

  @override
  ConsumerState<_DeviceOverviewCard> createState() =>
      _DeviceOverviewCardState();
}

class _DeviceOverviewCardState extends ConsumerState<_DeviceOverviewCard> {
  late Future<_DeviceOverviewData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DeviceOverviewData> _load() async {
    final identity = await DeviceIdentity.load();
    try {
      final devices = await ref.read(apiClientProvider).listDevices();
      return _DeviceOverviewData(identity: identity, devices: devices);
    } catch (error) {
      return _DeviceOverviewData(
        identity: identity,
        deviceError: error.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<_DeviceOverviewData>(
      future: _future,
      builder: (context, snapshot) {
        final identity = snapshot.data?.identity;
        final devices = snapshot.data?.devices;
        final deviceError = snapshot.data?.deviceError;
        final atLimit = devices != null &&
            devices.limit > 0 &&
            devices.total >= devices.limit;
        final registeredHere = identity != null &&
            devices != null &&
            devices.devices.any(
              (device) =>
                  (device.name ?? '').trim().toLowerCase() ==
                  identity.name.trim().toLowerCase(),
            );

        return Container(
          width: double.infinity,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusL),
                    ),
                    child: const Icon(
                      Icons.devices_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'This device',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        Text(
                          identity == null
                              ? 'Loading device identity...'
                              : '${identity.name} · ${identity.type}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: isDark
                                        ? AppColors.darkInkSoft
                                        : AppColors.inkMuted,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space3),
              Text(
                devices == null
                    ? (deviceError ?? 'Device slot information unavailable.')
                    : '${devices.total}/${devices.limit} device slots in use',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: AppSpacing.space1),
              Text(
                devices == null
                    ? 'Open Manage Devices to retry once the backend responds.'
                    : registeredHere
                        ? 'This device is already registered with the backend.'
                        : 'This device will register on the next profile refresh if a slot is available.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          isDark ? AppColors.darkInkSoft : AppColors.inkMuted,
                    ),
              ),
              if (atLimit) ...[
                const SizedBox(height: AppSpacing.space3),
                Text(
                  'Device limit reached. Remove an old device before connecting from a new install.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
              const SizedBox(height: AppSpacing.space4),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/devices'),
                  icon: const Icon(Icons.manage_accounts_outlined,
                      size: AppSpacing.iconXS),
                  label: const Text('Manage Devices'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DeviceOverviewData {
  const _DeviceOverviewData({
    required this.identity,
    this.devices,
    this.deviceError,
  });

  final DeviceIdentity identity;
  final DeviceListResult? devices;
  final String? deviceError;
}

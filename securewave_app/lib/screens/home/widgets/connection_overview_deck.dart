import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_plan.dart';
import '../../../core/models/vpn_protocol.dart';
import '../../../core/models/vpn_protocol_catalog.dart';
import '../../../core/services/auth_session.dart';
import '../../../core/state/app_state.dart';
import '../../../core/state/vpn_state.dart';
import '../../../core/vpn/protocol_capabilities.dart';
import '../../../ui/design/app_colors.dart';
import '../../../ui/design/app_spacing.dart';

const Set<VpnProtocol> _allConcreteProtocols = <VpnProtocol>{
  VpnProtocol.wireGuard,
  VpnProtocol.openVpn,
  VpnProtocol.ikev2,
};

class ConnectionOverviewDeck extends ConsumerWidget {
  const ConnectionOverviewDeck({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = ref.watch(authSessionProvider);
    final selectedProtocol =
        ref.watch(vpnStateProvider.select((s) => s.protocol));
    final selectedServerId =
        ref.watch(vpnStateProvider.select((s) => s.selectedServerId));
    final sessionBytes =
        ref.watch(vpnStateProvider.select((s) => s.sessionTransferredBytes));
    final lifetimeBytes =
        ref.watch(vpnStateProvider.select((s) => s.lifetimeTransferredBytes));
    final servers = ref.watch(serversProvider);
    final capabilities = ref.watch(vpnCapabilitiesProvider);
    final catalog = ref.watch(vpnProtocolCatalogProvider);
    final plan = ref.watch(userPlanProvider);

    final selectedServerLabel = servers.maybeWhen(
      data: (list) {
        for (final server in list) {
          if (server.id == selectedServerId) return server.name;
        }
        return null;
      },
      orElse: () => null,
    );

    final capsData = capabilities.valueOrNull;
    final catalogData = catalog.valueOrNull;
    final backendEnabled =
        catalogData?.enabledProtocols() ?? _allConcreteProtocols;
    final availabilityByProtocol = capsData == null
        ? <VpnProtocol, VpnProtocolAvailability>{}
        : <VpnProtocol, VpnProtocolAvailability>{
            for (final item in ProtocolCapabilityMatrix.evaluate(
              nativeCapabilities: capsData,
              backendEnabledProtocols: backendEnabled,
            ))
              item.protocol: item,
          };
    final catalogByProtocol = <VpnProtocol, VpnProtocolCatalogEntry>{
      for (final entry
          in catalogData?.protocols ?? const <VpnProtocolCatalogEntry>[])
        entry.protocol: entry,
    };
    final selectedAvailability = availabilityByProtocol[selectedProtocol];
    final selectedEntry = catalogByProtocol[selectedProtocol];
    final selectedHint =
        _selectedProtocolHint(selectedAvailability, selectedEntry);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurface.withValues(alpha: 0.84)
            : AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXXL),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : AppColors.ink)
                .withValues(alpha: isDark ? 0.16 : 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.space2,
            runSpacing: AppSpacing.space2,
            children: [
              _MetaChip(
                icon: auth.isAuthenticated
                    ? Icons.verified_user_outlined
                    : Icons.lock_outline_rounded,
                label: auth.isAuthenticated ? 'Signed in' : 'Signed out',
                value: auth.email ?? 'Session ready',
                tone: auth.isAuthenticated
                    ? AppColors.success
                    : AppColors.warning,
              ),
              _MetaChip(
                icon: Icons.public_rounded,
                label: 'Location',
                value: selectedServerLabel ?? 'Auto (Fastest)',
                tone: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          Text(
            'Protocol',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AppSpacing.space2),
          Wrap(
            spacing: AppSpacing.space2,
            runSpacing: AppSpacing.space2,
            children: [
              _ProtocolChip(
                label: vpnProtocolLabel(VpnProtocol.auto),
                selected: selectedProtocol == VpnProtocol.auto,
                enabled: true,
                onTap: () => ref
                    .read(vpnStateProvider.notifier)
                    .selectProtocol(VpnProtocol.auto),
              ),
              for (final protocol
                  in ProtocolCapabilityMatrix.orderedProtocols())
                _ProtocolChip(
                  label: vpnProtocolLabel(protocol),
                  selected: selectedProtocol == protocol,
                  enabled: availabilityByProtocol[protocol]?.available ??
                      capsData == null,
                  onTap: () => ref
                      .read(vpnStateProvider.notifier)
                      .selectProtocol(protocol),
                ),
            ],
          ),
          if (selectedProtocol != VpnProtocol.auto && selectedHint != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.space2),
              child: Text(
                selectedHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          isDark ? AppColors.darkInkSoft : AppColors.inkMuted,
                    ),
              ),
            ),
          const SizedBox(height: AppSpacing.space4),
          plan.when(
            data: (value) => _UsagePanel(
              plan: value,
              sessionBytes: sessionBytes,
              lifetimeBytes: lifetimeBytes,
              isDark: isDark,
            ),
            loading: () => _UsagePanel(
              sessionBytes: sessionBytes,
              lifetimeBytes: lifetimeBytes,
              isDark: isDark,
            ),
            error: (_, __) => _UsagePanel(
              sessionBytes: sessionBytes,
              lifetimeBytes: lifetimeBytes,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  String? _selectedProtocolHint(
    VpnProtocolAvailability? availability,
    VpnProtocolCatalogEntry? entry,
  ) {
    if (availability?.available == true) {
      return 'Ready on this device and enabled by the backend.';
    }
    final reason = entry?.reason?.trim();
    if (reason != null && reason.isNotEmpty) return reason;
    return availability?.unavailableReason;
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: AppSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
        border: Border.all(color: tone.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: AppSpacing.space2),
          Text(
            '$label: $value',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _ProtocolChip extends StatelessWidget {
  const _ProtocolChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: enabled ? (_) => onTap() : null,
      showCheckmark: false,
    );
  }
}

class _UsagePanel extends StatelessWidget {
  const _UsagePanel({
    this.plan,
    required this.sessionBytes,
    required this.lifetimeBytes,
    required this.isDark,
  });

  final UserPlan? plan;
  final int sessionBytes;
  final int lifetimeBytes;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final effectiveUsedBytes = plan == null
        ? null
        : (plan!.usedBytes + sessionBytes).clamp(0, plan!.dataCapBytes).toInt();
    final progress = (plan == null ||
            plan!.isUnlimited ||
            plan!.dataCapBytes <= 0)
        ? 0.0
        : (effectiveUsedBytes! / plan!.dataCapBytes).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Usage',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          plan == null
              ? 'Plan usage unavailable right now.'
              : plan!.isUnlimited
                  ? 'Unlimited plan active.'
                  : '${_formatBytes(effectiveUsedBytes!)} used of ${_formatBytes(plan!.dataCapBytes)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isDark ? AppColors.darkInkSoft : AppColors.inkMuted,
              ),
        ),
        const SizedBox(height: AppSpacing.space2),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          child: SizedBox(
            height: 8,
            child: LinearProgressIndicator(
              value: plan == null || plan!.isUnlimited ? 0 : progress,
              backgroundColor: isDark ? AppColors.darkBorder : AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress >= 0.9
                    ? AppColors.error
                    : progress >= 0.7
                        ? AppColors.warning
                        : AppColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space3),
        Wrap(
          spacing: AppSpacing.space4,
          runSpacing: AppSpacing.space2,
          children: [
            Text(
              'Session: ${_formatBytes(sessionBytes)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'This device: ${_formatBytes(lifetimeBytes)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}

String _formatBytes(int bytes) {
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

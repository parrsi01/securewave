part of '../app.dart';

class _ConnectionStrip extends StatelessWidget {
  const _ConnectionStrip({required this.status, required this.protocol});

  final _StatusDescriptor status;
  final VpnProtocol protocol;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: '${status.label}. ${vpnProtocolLabel(protocol)} selected.',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: status.background,
          border: Border.all(color: status.border),
          borderRadius: BorderRadius.circular(FreshTheme.radius),
        ),
        child: Row(
          children: [
            Icon(status.icon, color: status.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    vpnProtocolLabel(protocol),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            _StatusChip(label: status.shortLabel, tone: status.tone),
          ],
        ),
      ),
    );
  }
}

class _UsageSummary extends StatelessWidget {
  const _UsageSummary({required this.plan});

  final UserPlan plan;

  @override
  Widget build(BuildContext context) {
    final percent = plan.usagePercent.isFinite
        ? plan.usagePercent.clamp(0.0, 1.0).toDouble()
        : 0.0;
    final percentText =
        plan.isUnlimited ? 'Unlimited' : '${(percent * 100).round()}%';
    final cap = plan.isUnlimited || plan.dataCapGb <= 0
        ? 'Unlimited'
        : '${plan.dataCapGb.toStringAsFixed(0)} GB';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                plan.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _StatusChip(
              label: plan.isPremium ? 'Premium' : 'Free',
              tone: plan.isPremium ? _Tone.info : _Tone.neutral,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Semantics(
          label: 'Usage $percentText',
          child: LinearProgressIndicator(
            value: plan.isUnlimited ? 1 : percent,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            color: FreshTheme.primary,
            backgroundColor: FreshTheme.surfaceMuted,
          ),
        ),
        const SizedBox(height: 12),
        _InfoRow('Used', '${plan.usedGb.toStringAsFixed(1)} GB'),
        _InfoRow('Cap', cap),
        _InfoRow('Usage', percentText),
      ],
    );
  }
}

class _ProtocolPicker extends ConsumerWidget {
  const _ProtocolPicker({
    required this.selected,
    required this.servers,
    required this.selectedServerId,
  });

  final VpnProtocol selected;
  final AsyncValue<List<ServerRegion>> servers;
  final String? selectedServerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnService = ref.watch(vpnServiceProvider);
    final backendAvailability = ref.watch(protocolAvailabilityProvider);
    final protocols = [
      (
        protocol: VpnProtocol.wireGuard,
        title: 'WireGuard',
        detail: 'Primary Linux runtime path.',
      ),
      (
        protocol: VpnProtocol.openVpn,
        title: 'OpenVPN',
        detail: 'Requires a backend-issued OpenVPN profile.',
      ),
      (
        protocol: VpnProtocol.ikev2,
        title: 'IKEv2/IPSec',
        detail: 'Requires a backend-issued IKEv2 profile and strongSwan.',
      ),
    ];

    return Column(
      children: [
        for (var i = 0; i < protocols.length; i++) ...[
          Builder(
            builder: (context) {
              final item = protocols[i];
              final availability = _protocolAvailability(
                protocol: item.protocol,
                service: vpnService,
                backendAvailability: backendAvailability,
                servers: servers,
                selectedServerId: selectedServerId,
              );
              return _ProtocolTile(
                protocol: item.protocol,
                selected: selected == item.protocol,
                title: item.title,
                detail: availability.canConnect
                    ? item.detail
                    : availability.message,
                enabled: availability.canConnect,
                pending: availability.backendEvidencePending,
              );
            },
          ),
          if (i < protocols.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ProtocolTile extends ConsumerWidget {
  const _ProtocolTile({
    required this.protocol,
    required this.selected,
    required this.title,
    required this.detail,
    required this.enabled,
    required this.pending,
  });

  final VpnProtocol protocol;
  final bool selected;
  final String title;
  final String detail;
  final bool enabled;
  final bool pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SelectableRow(
      selected: selected,
      enabled: enabled,
      title: title,
      subtitle: detail,
      trailing: pending
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : enabled
              ? null
              : const _StatusChip(label: 'Unavailable', tone: _Tone.warning),
      onTap: enabled
          ? () => ref.read(vpnStateProvider.notifier).selectProtocol(protocol)
          : null,
    );
  }
}

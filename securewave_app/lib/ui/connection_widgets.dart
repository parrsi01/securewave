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

class _WireGuardInfo extends StatelessWidget {
  const _WireGuardInfo();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.shield_outlined),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'WireGuard is the only protocol included in this Linux beta.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const _StatusChip(label: 'Selected', tone: _Tone.info),
      ],
    );
  }
}

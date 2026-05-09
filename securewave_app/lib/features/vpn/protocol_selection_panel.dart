import 'package:flutter/material.dart';

import '../../core/models/vpn_protocol.dart';
import '../../ui/app_ui_v1.dart';

class ProtocolSelectionPanel extends StatelessWidget {
  const ProtocolSelectionPanel({
    super.key,
    required this.selectedProtocol,
    required this.onSelect,
    this.dense = false,
  });

  final VpnProtocol selectedProtocol;
  final ValueChanged<VpnProtocol> onSelect;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final hasBlockedSelection = selectedProtocol != VpnProtocol.wireGuard;
    const options = [
      _ProtocolOption(
        protocol: VpnProtocol.wireGuard,
        icon: Icons.bolt_rounded,
        name: 'WireGuard',
        status: 'Public RC',
        description: 'Primary SecureWave tunnel for this release candidate.',
        enabled: true,
        color: AppUIv1.accentCyan,
      ),
      _ProtocolOption(
        protocol: VpnProtocol.openVpn,
        icon: Icons.vpn_lock_rounded,
        name: 'OpenVPN',
        status: 'Restricted',
        description:
            'Covered Linux helper path only. Not public-selectable here.',
        enabled: false,
        color: AppUIv1.warning,
      ),
      _ProtocolOption(
        protocol: VpnProtocol.ikev2,
        icon: Icons.lock_clock_rounded,
        name: 'IKEv2/IPSec',
        status: 'Not public v1',
        description: 'Kept out of the public release-candidate UI.',
        enabled: false,
        color: AppUIv1.inkSoft,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasBlockedSelection) ...[
          SecureSurface(
            variant: SecureSurfaceVariant.warning,
            padding: const EdgeInsets.all(AppUIv1.space3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppUIv1.warning,
                  size: 20,
                ),
                const SizedBox(width: AppUIv1.space2),
                Expanded(
                  child: Text(
                    'The saved protocol is not public-ready. Select WireGuard before connecting.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppUIv1.warning),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppUIv1.space3),
        ],
        for (final option in options) ...[
          _ProtocolCard(
            option: option,
            selected: option.protocol == selectedProtocol,
            dense: dense,
            onTap: option.enabled ? () => onSelect(option.protocol) : null,
          ),
          if (option != options.last) const SizedBox(height: AppUIv1.space3),
        ],
      ],
    );
  }
}

class _ProtocolCard extends StatelessWidget {
  const _ProtocolCard({
    required this.option,
    required this.selected,
    required this.dense,
    required this.onTap,
  });

  final _ProtocolOption option;
  final bool selected;
  final bool dense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = option.enabled;
    final borderColor = selected
        ? option.color.withValues(alpha: 0.78)
        : AppUIv1.border.withValues(alpha: active ? 1 : 0.55);
    final surfaceColor = selected
        ? option.color.withValues(alpha: 0.12)
        : AppUIv1.surfaceRaised.withValues(alpha: active ? 0.78 : 0.38);

    return AnimatedContainer(
      duration: AppUIv1.durationNormal,
      curve: AppUIv1.curveDefault,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(AppUIv1.radiusCard),
        border: Border.all(
          color: borderColor,
          width: selected ? AppUIv1.strokeStrong : AppUIv1.hairline,
        ),
        boxShadow: selected ? AppUIv1.glowAccent : AppUIv1.shadowSm,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppUIv1.radiusCard),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(dense ? AppUIv1.space3 : AppUIv1.space4),
            child: Opacity(
              opacity: active || selected ? 1 : 0.62,
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: AppUIv1.durationFast,
                    width: dense ? 38 : 44,
                    height: dense ? 38 : 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: option.color
                          .withValues(alpha: selected ? 0.22 : 0.12),
                      border: Border.all(
                        color: option.color
                            .withValues(alpha: selected ? 0.5 : 0.24),
                      ),
                    ),
                    child: Icon(
                      option.enabled ? option.icon : Icons.lock_outline_rounded,
                      color: option.color,
                      size: dense ? 19 : 21,
                    ),
                  ),
                  const SizedBox(width: AppUIv1.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                option.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(color: AppUIv1.ink),
                              ),
                            ),
                            SecureStatePill(
                              label: selected ? 'Selected' : option.status,
                              color: selected ? option.color : AppUIv1.inkSoft,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppUIv1.space1),
                        Text(
                          option.description,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProtocolOption {
  const _ProtocolOption({
    required this.protocol,
    required this.icon,
    required this.name,
    required this.status,
    required this.description,
    required this.enabled,
    required this.color,
  });

  final VpnProtocol protocol;
  final IconData icon;
  final String name;
  final String status;
  final String description;
  final bool enabled;
  final Color color;
}

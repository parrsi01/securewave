import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/vpn_protocol.dart';
import '../../core/state/vpn_state.dart';
import '../widgets/glass_panel.dart';

class ConnectionOverviewDeck extends ConsumerWidget {
  const ConnectionOverviewDeck({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(vpnStateProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = <Widget>[
          _OverviewStat(
            label: 'State',
            value: state.statusText(),
          ),
          _OverviewStat(
            label: 'Protocol',
            value: _protocolLabel(state.effectiveProtocol ?? state.protocol),
          ),
          _OverviewStat(
            label: 'Tunnel health',
            value: '${(state.stabilityScore * 100).round()}%',
          ),
          _OverviewStat(
            label: 'Selected server',
            value: (state.selectedServerId ?? 'Automatic').trim().isEmpty
                ? 'Automatic'
                : (state.selectedServerId ?? 'Automatic'),
          ),
        ];
        final wide = constraints.maxWidth >= 720;
        return GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          crossAxisCount: wide ? 4 : 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: wide ? 1.25 : 1.55,
          children: cards,
        );
      },
    );
  }

  static String _protocolLabel(VpnProtocol protocol) {
    return switch (protocol) {
      VpnProtocol.auto => 'Automatic',
      VpnProtocol.wireGuard => 'WireGuard',
      VpnProtocol.openVpn => 'OpenVPN',
      VpnProtocol.ikev2 => 'IKEv2',
    };
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/vpn_protocol.dart';
import '../../core/models/vpn_status.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../theme/securewave_palette.dart';
import '../widgets/glass_panel.dart';
import '../widgets/status_badge.dart';

class StatusDisplay extends ConsumerWidget {
  const StatusDisplay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(vpnStateProvider);
    final servers = ref.watch(serversProvider);
    final selectedServer = servers.maybeWhen(
      data: (items) {
        final selectedId = (state.selectedServerId ?? '').trim();
        if (selectedId.isEmpty) return null;
        for (final item in items) {
          if (item.id == selectedId) return item;
        }
        return null;
      },
      orElse: () => null,
    );
    final allRegionsDown = servers.maybeWhen(
      data: (items) =>
          items.isNotEmpty &&
          items.every(
            (item) =>
                (item.regionHealthStatus ?? '').trim().toLowerCase() == 'down',
          ),
      orElse: () => false,
    );
    final selectedRegionDown = servers.maybeWhen(
      data: (items) {
        final selectedId = (state.selectedServerId ?? '').trim();
        if (selectedId.isEmpty) return false;
        for (final item in items) {
          if (item.id != selectedId) continue;
          return (item.regionHealthStatus ?? '').trim().toLowerCase() == 'down';
        }
        return false;
      },
      orElse: () => false,
    );
    final badges = <Widget>[
      StatusBadge(
        label: state.statusText(),
        color: state.statusColor,
        icon: state.statusIcon,
      ),
      StatusBadge(
        label: _protocolLabel(state.effectiveProtocol ?? state.protocol),
        color: Theme.of(context).colorScheme.primary,
      ),
      StatusBadge(
        label:
            '${(state.dataRateDown + state.dataRateUp).toStringAsFixed(2)} Mbps',
        color: SecureWavePalette.mint,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (allRegionsDown)
          const _Banner(
            text: 'No servers available',
            color: SecureWavePalette.danger,
          )
        else if (selectedRegionDown &&
            state.status != VpnStatus.connected &&
            state.status != VpnStatus.connecting)
          const _Banner(
            text: 'Selected region is offline',
            color: SecureWavePalette.warning,
          ),
        if (state.failoverActive && state.status == VpnStatus.connected)
          const _Banner(
            text: 'Primary server unavailable. Connected via fallback region.',
            color: SecureWavePalette.warning,
          ),
        if (state.failoverActive &&
            state.status == VpnStatus.connected &&
            selectedServer != null) ...<Widget>[
          _Banner(
            text: 'Connected region: ${selectedServer.name}',
            color: SecureWavePalette.success,
          ),
          _Banner(
            text: _failoverRegionLabel(selectedServer.regionGroup),
            color: SecureWavePalette.warning,
          ),
        ],
        if (!state.failoverActive &&
            state.status == VpnStatus.connected &&
            (selectedServer?.regionGroup ?? '').trim().toLowerCase() ==
                'north_america')
          const _Banner(
            text: 'Optimized for Caribbean routing',
            color: SecureWavePalette.success,
          ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: badges,
              ),
              const SizedBox(height: 20),
              Text(
                _headline(state),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _detail(state),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (state.errorMessage != null &&
                  state.status == VpnStatus.error) ...<Widget>[
                const SizedBox(height: 18),
                Text(
                  state.errorMessage!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: SecureWavePalette.danger,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ],
          ),
        ),
      ],
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

  static String _headline(VpnState state) {
    return switch (state.status) {
      VpnStatus.connected => 'Tunnel online',
      VpnStatus.connecting => 'Negotiating secure route',
      VpnStatus.disconnecting => 'Closing secure route',
      VpnStatus.disconnected => 'Ready when you are',
      VpnStatus.error => state.statusText(),
    };
  }

  static String _detail(VpnState state) {
    final selected = (state.selectedServerId ?? '').trim();
    if (state.status == VpnStatus.connected) {
      return selected.isEmpty
          ? 'Connected using the best available SecureWave route.'
          : 'Connected through $selected.';
    }
    if (state.status == VpnStatus.connecting) {
      return 'Profile provisioning, runtime checks, and handshake validation are in progress.';
    }
    if (state.status == VpnStatus.disconnecting) {
      return 'The active VPN route is being removed and traffic counters are being finalized.';
    }
    if (state.status == VpnStatus.error) {
      return 'Open Diagnostics for backend, auth, and tunnel-level detail.';
    }
    return selected.isEmpty
        ? 'Choose a location or connect with automatic routing.'
        : 'Prepared for $selected.';
  }

  static String _failoverRegionLabel(String? rawRegionGroup) {
    final normalized = (rawRegionGroup ?? '').trim().toLowerCase();
    return switch (normalized) {
      'europe' => 'Using European fallback',
      'north_america' => 'Using North American fallback',
      'south_america' => 'Using South American fallback',
      'asia' => 'Using Asian fallback',
      'oceania' => 'Using Oceania fallback',
      'africa' => 'Using African fallback',
      _ => 'Using fallback region',
    };
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

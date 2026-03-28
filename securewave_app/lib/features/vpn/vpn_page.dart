import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/models/vpn_protocol.dart';
import '../../core/models/vpn_status.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_ui_v1.dart';
import '../../ui/connect_button.dart';
import '../../ui/components/depth_panel.dart';
import '../../ui/connection_card.dart';
import '../../ui/traffic_stats_card.dart';
import '../../ui/usage_meter.dart';

class VpnPage extends HookConsumerWidget {
  const VpnPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final servers = ref.watch(serversProvider);
    final plan = ref.watch(userPlanProvider);
    final downHistory = useState<List<double>>(<double>[]);
    final upHistory = useState<List<double>>(<double>[]);

    useEffect(() {
      final nextDown = [...downHistory.value, vpnState.dataRateDown / 1024];
      final nextUp = [...upHistory.value, vpnState.dataRateUp / 1024];
      downHistory.value = nextDown.length > 12
          ? nextDown.sublist(nextDown.length - 12)
          : nextDown;
      upHistory.value =
          nextUp.length > 12 ? nextUp.sublist(nextUp.length - 12) : nextUp;
      return null;
    }, [vpnState.dataRateDown, vpnState.dataRateUp]);

    final serverLabel = servers.maybeWhen(
      data: (items) {
        if (items.isEmpty) return 'No server selected';
        final selected =
            items.where((server) => server.id == vpnState.selectedServerId);
        if (selected.isEmpty) return items.first.name;
        return selected.first.name;
      },
      orElse: () => 'Loading server list',
    );

    final statusLabel = switch (vpnState.status) {
      VpnStatus.connected => 'Connected',
      VpnStatus.connecting => 'Connecting',
      VpnStatus.verifying => 'Verifying',
      VpnStatus.disconnecting => 'Disconnecting',
      VpnStatus.reconnecting => 'Reconnecting',
      VpnStatus.degraded => 'Degraded',
      VpnStatus.error => 'Action required',
      VpnStatus.disconnected => 'Disconnected',
    };

    final phaseLabel = switch (vpnState.connectPhase) {
      null => null,
      ConnectPhase.authenticating => 'Authenticating',
      ConnectPhase.checkingBackend => 'Checking backend',
      ConnectPhase.resolvingProtocol => 'Resolving protocol',
      ConnectPhase.fetchingProfile => 'Fetching profile',
      ConnectPhase.establishingTunnel => 'Establishing tunnel',
      ConnectPhase.verifyingConnection => 'Verifying connection',
    };

    final protocolLabel = vpnState.protocol == VpnProtocol.auto
        ? 'Auto${vpnState.effectiveProtocol == null ? '' : ' → ${vpnProtocolLabel(vpnState.effectiveProtocol!)}'}'
        : vpnProtocolLabel(vpnState.effectiveProtocol ?? vpnState.protocol);

    final isConnected = vpnState.status == VpnStatus.connected;
    final trafficNote = !isConnected
        ? (vpnState.protocolMessage ?? vpnState.reconnectReason)
        : (vpnState.dataRateDown == 0 && vpnState.dataRateUp == 0
            ? 'Connected, but no traffic detected yet.'
            : null);

    Future<void> onPrimaryAction() async {
      if (vpnState.status == VpnStatus.connected) {
        await ref.read(vpnStateProvider.notifier).disconnect();
      } else {
        await ref.read(vpnStateProvider.notifier).connect();
      }
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppUIv1.space5),
        children: [
          Text('SecureWave', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: AppUIv1.space2),
          Text(
            'One tap protection with live tunnel diagnostics and traffic telemetry.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppUIv1.space5),
          Center(
            child: ConnectButton(
              status: vpnState.status,
              isBusy: vpnState.isBusy,
              onPressed: () => unawaited(onPrimaryAction()),
            ),
          )
              .animate()
              .fadeIn(duration: 300.ms)
              .scale(begin: const Offset(0.96, 0.96)),
          const SizedBox(height: AppUIv1.space5),
          ConnectionCard(
            status: vpnState.status,
            statusLabel: statusLabel,
            serverLabel: serverLabel,
            protocolLabel: protocolLabel,
            durationLabel: vpnState.lastTunnelStartAt == null
                ? '--:--:--'
                : AppUIv1.formatDuration(
                    DateTime.now().difference(vpnState.lastTunnelStartAt!)),
            stageLabel: phaseLabel ?? 'Idle',
            detail: vpnState.killSwitchActive
                ? vpnState.reconnectReason
                : vpnState.protocolMessage,
          ),
          const SizedBox(height: AppUIv1.space4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/servers'),
                  icon: const Icon(Icons.public),
                  label: const Text('Choose server'),
                ),
              ),
              const SizedBox(width: AppUIv1.space3),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.push('/connection'),
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Connection details'),
                ),
              ),
            ],
          ),
          if (vpnState.desiredOn &&
              vpnState.status != VpnStatus.connected &&
              vpnState.reconnectPending) ...[
            const SizedBox(height: AppUIv1.space3),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: vpnState.isBusy
                    ? null
                    : () =>
                        ref.read(vpnStateProvider.notifier).forceReconnect(),
                icon: const Icon(Icons.refresh),
                label: const Text('Reconnect now'),
              ),
            ),
          ],
          if (vpnState.errorMessage != null) ...[
            const SizedBox(height: AppUIv1.space3),
            DepthPanel(
              depth: PanelDepth.base,
              padding: const EdgeInsets.all(AppUIv1.space3),
              child: Text(
                vpnState.errorMessage!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppUIv1.warning),
              ),
            ),
          ],
          const SizedBox(height: AppUIv1.space4),
          TrafficStatsCard(
            downloadLabel: AppUIv1.formatBytes(vpnState.dataRateDown),
            uploadLabel: AppUIv1.formatBytes(vpnState.dataRateUp),
            downloadPoints: downHistory.value,
            uploadPoints: upHistory.value,
            sessionUsageLabel:
                AppUIv1.formatDataAmount(vpnState.sessionTransferredBytes),
            lifetimeUsageLabel:
                AppUIv1.formatDataAmount(vpnState.lifetimeTransferredBytes),
            note: trafficNote,
          ),
          const SizedBox(height: AppUIv1.space4),
          plan.when(
            data: (data) => UsageMeter(
              label: 'Plan usage',
              usagePercent: data.usagePercent,
              caption:
                  '${data.usedGb.toStringAsFixed(1)} GB used of ${data.dataCapGb.toStringAsFixed(0)} GB',
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const UsageMeter(
              label: 'Plan usage',
              usagePercent: 0,
              caption: 'Usage data unavailable.',
            ),
          ),
        ],
      ),
    );
  }
}

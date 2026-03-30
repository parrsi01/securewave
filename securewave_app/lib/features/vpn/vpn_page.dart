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

    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // ── Status header ─────────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isConnected
                          ? AppUIv1.success
                          : vpnState.status == VpnStatus.error
                              ? AppUIv1.danger
                              : AppUIv1.inkSoft,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      statusLabel,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  if (phaseLabel != null)
                    Text(
                      phaseLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Connect button ────────────────────────────────────────────────
          Center(
            child: ConnectButton(
              status: vpnState.status,
              isBusy: vpnState.isBusy,
              onPressed: () => unawaited(onPrimaryAction()),
            ),
          ).animate().fadeIn(duration: 300.ms).scale(
                begin: const Offset(0.96, 0.96),
              ),

          const SizedBox(height: 20),

          // ── Stats row — download / upload / ping ──────────────────────────
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.arrow_downward_rounded,
                  label: 'Download',
                  value: AppUIv1.formatBytes(vpnState.dataRateDown),
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  icon: Icons.arrow_upward_rounded,
                  label: 'Upload',
                  value: AppUIv1.formatBytes(vpnState.dataRateUp),
                  color: cs.secondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  icon: Icons.timer_outlined,
                  label: 'Session',
                  value: vpnState.lastTunnelStartAt == null
                      ? '--:--'
                      : AppUIv1.formatDuration(
                          DateTime.now()
                              .difference(vpnState.lastTunnelStartAt!),
                        ),
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Server selector ───────────────────────────────────────────────
          Card(
            child: ListTile(
              leading: const Icon(Icons.public_rounded),
              title: const Text('Server'),
              subtitle: Text(serverLabel),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/servers'),
            ),
          ),

          const SizedBox(height: 8),

          // ── Protocol badge ────────────────────────────────────────────────
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_rounded),
              title: const Text('Protocol'),
              subtitle: Text(protocolLabel),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/connection'),
            ),
          ),

          // ── Reconnect now (conditional) ───────────────────────────────────
          if (vpnState.desiredOn &&
              vpnState.status != VpnStatus.connected &&
              vpnState.reconnectPending) ...[
            const SizedBox(height: 12),
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

          // ── Error message ─────────────────────────────────────────────────
          if (vpnState.errorMessage != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 18, color: AppUIv1.warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        vpnState.errorMessage!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppUIv1.warning,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // ── Traffic note ──────────────────────────────────────────────────
          if (trafficNote != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                trafficNote,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ),

          // ── Plan usage ────────────────────────────────────────────────────
          plan.when(
            data: (data) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Plan usage',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${data.usedGb.toStringAsFixed(1)} / ${data.dataCapGb.toStringAsFixed(0)} GB',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: data.usagePercent,
                        minHeight: 8,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

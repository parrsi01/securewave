import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/models/server_region.dart';
import '../../core/models/vpn_protocol.dart';
import '../../core/models/vpn_status.dart';
import '../../core/state/client_settings_state.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_ui_v1.dart';
import '../../ui/components/connect_button.dart';
import '../../ui/components/dashboard_card.dart';
import '../../ui/components/section_container.dart';
import '../../ui/components/status_indicator.dart';
import '../../ui/components/traffic_card.dart';
import '../../ui/layout/adaptive_shell_scaffold.dart';
import '../../ui/theme/breakpoints.dart';
import '../../ui/theme/spacing.dart';

class VpnPage extends HookConsumerWidget {
  const VpnPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final servers = ref.watch(serversProvider);
    final plan = ref.watch(userPlanProvider);
    final settings = ref.watch(clientSettingsProvider);
    final breakpoint = SecureWaveBreakpoints.of(context);
    final downHistory = useState<List<double>>(<double>[]);
    final upHistory = useState<List<double>>(<double>[]);

    useEffect(() {
      downHistory.value = _appendSample(
        downHistory.value,
        vpnState.dataRateDown / 1024,
      );
      upHistory.value = _appendSample(
        upHistory.value,
        vpnState.dataRateUp / 1024,
      );
      return null;
    }, [vpnState.dataRateDown, vpnState.dataRateUp]);

    final selectedServer = servers.maybeWhen(
      data: (items) => items.firstWhere(
        (server) => server.id == vpnState.selectedServerId,
        orElse: () => items.isEmpty ? _placeholderServer : items.first,
      ),
      orElse: () => _placeholderServer,
    );

    final statusLabel = switch (vpnState.status) {
      VpnStatus.connected => 'Connected',
      VpnStatus.connecting => 'Connecting',
      VpnStatus.disconnecting => 'Disconnecting',
      VpnStatus.reconnecting => 'Reconnecting',
      VpnStatus.error => 'Needs attention',
      VpnStatus.disconnected => 'Disconnected',
    };

    final protocolLabel = vpnState.protocol == VpnProtocol.auto
        ? 'Auto${vpnState.activeProtocol == null ? '' : ' → ${vpnProtocolLabel(vpnState.activeProtocol!)}'}'
        : vpnProtocolLabel(vpnState.activeProtocol ?? vpnState.protocol);

    final latencyLabel = selectedServer.latencyMs == null
        ? 'Unknown latency'
        : '${selectedServer.latencyMs} ms';

    final note = vpnState.status == VpnStatus.connected &&
            vpnState.dataRateDown == 0 &&
            vpnState.dataRateUp == 0
        ? 'Connected, but no traffic detected yet.'
        : (vpnState.networkLockActive
            ? vpnState.networkLockReason
            : vpnState.statusDetail);

    Future<void> onPrimaryAction() async {
      if (vpnState.status == VpnStatus.connected) {
        await ref.read(vpnStateProvider.notifier).disconnect();
      } else {
        await ref.read(vpnStateProvider.notifier).connect();
      }
    }

    return AdaptiveShellScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionContainer(
            title: 'SecureWave',
            subtitle:
                'Minimal protection with a one-click dashboard built for phone, tablet, and desktop.',
            trailing: StatusIndicator(
              status: vpnState.status,
              label: statusLabel,
            ),
            child: DashboardCard(
              child: Column(
                children: [
                  _StatusHeader(
                    location: selectedServer.name.isEmpty
                        ? 'No server selected'
                        : selectedServer.name,
                    latency: latencyLabel,
                    protocol: protocolLabel,
                  ),
                  const SizedBox(height: SecureWaveSpacing.xl),
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
                  const SizedBox(height: SecureWaveSpacing.xl),
                  Wrap(
                    spacing: SecureWaveSpacing.md,
                    runSpacing: SecureWaveSpacing.md,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: () => context.push('/servers'),
                        icon: const Icon(Icons.public_rounded),
                        label: const Text('Select server'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => context.push('/connection'),
                        icon: const Icon(Icons.insights_rounded),
                        label: const Text('Connection details'),
                      ),
                      if (vpnState.desiredOn &&
                          vpnState.status != VpnStatus.connected &&
                          settings.autoReconnect)
                        FilledButton.tonalIcon(
                          onPressed: vpnState.isBusy
                              ? null
                              : () => ref
                                  .read(vpnStateProvider.notifier)
                                  .reconnectNow(),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reconnect now'),
                        ),
                    ],
                  ),
                  if (vpnState.errorMessage != null || note != null) ...[
                    const SizedBox(height: SecureWaveSpacing.lg),
                    Text(
                      vpnState.errorMessage ?? note ?? '',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: vpnState.errorMessage != null
                                ? AppUIv1.warning
                                : AppUIv1.inkMuted,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: SecureWaveSpacing.xl),
          _MetricSection(
            breakpoint: breakpoint,
            downloadLabel: AppUIv1.formatBytes(vpnState.dataRateDown),
            uploadLabel: AppUIv1.formatBytes(vpnState.dataRateUp),
            usageLabel: AppUIv1.formatDataAmount(
              vpnState.sessionDownloadBytes + vpnState.sessionUploadBytes,
            ),
            lifetimeLabel: AppUIv1.formatDataAmount(
              vpnState.lifetimeDownloadBytes + vpnState.lifetimeUploadBytes,
            ),
            durationLabel: AppUIv1.formatDuration(vpnState.connectionDuration),
            downHistory: downHistory.value,
            upHistory: upHistory.value,
          ),
          const SizedBox(height: SecureWaveSpacing.xl),
          SectionContainer(
            title: 'Plan usage',
            subtitle:
                'Session usage stays visible without stretching on desktop.',
            child: plan.when(
              data: (data) => DashboardCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${data.usedGb.toStringAsFixed(1)} GB used of ${data.dataCapGb.toStringAsFixed(0)} GB',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: SecureWaveSpacing.md),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: data.usagePercent,
                        minHeight: 12,
                        backgroundColor: AppUIv1.surfaceMuted,
                        color: AppUIv1.accent,
                      ),
                    ),
                    const SizedBox(height: SecureWaveSpacing.sm),
                    Text(
                      '${data.remainingGb.toStringAsFixed(1)} GB remaining',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              loading: () => const DashboardCard(
                child: SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (_, __) => const DashboardCard(
                child: Text('Usage data unavailable right now.'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<double> _appendSample(List<double> values, double next) {
    final updated = <double>[...values, next];
    if (updated.length > 18) {
      return updated.sublist(updated.length - 18);
    }
    return updated;
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.location,
    required this.latency,
    required this.protocol,
  });

  final String location;
  final String latency;
  final String protocol;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: SecureWaveSpacing.md,
      runSpacing: SecureWaveSpacing.md,
      alignment: WrapAlignment.spaceBetween,
      children: [
        _HeaderMetric(label: 'Server', value: location),
        _HeaderMetric(label: 'Latency', value: latency),
        _HeaderMetric(label: 'Protocol', value: protocol),
      ],
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: SecureWaveSpacing.xs),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _MetricSection extends StatelessWidget {
  const _MetricSection({
    required this.breakpoint,
    required this.downloadLabel,
    required this.uploadLabel,
    required this.usageLabel,
    required this.lifetimeLabel,
    required this.durationLabel,
    required this.downHistory,
    required this.upHistory,
  });

  final SecureWaveBreakpoint breakpoint;
  final String downloadLabel;
  final String uploadLabel;
  final String usageLabel;
  final String lifetimeLabel;
  final String durationLabel;
  final List<double> downHistory;
  final List<double> upHistory;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      Expanded(
        child: TrafficCard(
          label: 'Download',
          value: downloadLabel,
          accent: AppUIv1.accentStrong,
          icon: Icons.south_rounded,
          points: downHistory,
          caption: 'Live traffic',
        ),
      ),
      Expanded(
        child: TrafficCard(
          label: 'Upload',
          value: uploadLabel,
          accent: AppUIv1.accentSun,
          icon: Icons.north_rounded,
          points: upHistory,
          caption: 'Live traffic',
        ),
      ),
      Expanded(
        child: DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Session usage',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: SecureWaveSpacing.md),
              Text(
                usageLabel,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: SecureWaveSpacing.sm),
              Text(
                'Lifetime $lifetimeLabel',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: SecureWaveSpacing.sm),
              Text(
                'Duration $durationLabel',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ];

    return SectionContainer(
      title: 'Metrics',
      subtitle:
          'Download, upload, and session usage resize across mobile, tablet, and desktop.',
      child: breakpoint == SecureWaveBreakpoint.mobile
          ? Column(
              children: [
                for (final card in cards) ...[
                  SizedBox(width: double.infinity, child: card),
                  if (card != cards.last)
                    const SizedBox(height: SecureWaveSpacing.md),
                ],
              ],
            )
          : Row(
              children: [
                for (var index = 0; index < cards.length; index++) ...[
                  cards[index],
                  if (index != cards.length - 1)
                    const SizedBox(width: SecureWaveSpacing.md),
                ],
              ],
            ),
    );
  }
}

const _placeholderServer = ServerRegion(id: '', name: '');

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/models/vpn_protocol.dart';
import '../../core/models/vpn_status.dart';
import '../../core/state/vpn_state.dart';
import '../components/connection_card.dart';
import '../components/connect_button.dart';
import '../components/status_indicator.dart';
import '../components/traffic_stats_card.dart';
import '../components/usage_meter.dart';
import '../layout/page_frame.dart';
import '../theme/securewave_theme.dart';
import '../widgets/glass_panel.dart';
import '../widgets/ui_helpers.dart';
import '../widgets/vpn_ui_bindings.dart';

class HomeScreen extends HookConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnStateProvider);
    final selectedServer = ref.watch(selectedServerProvider);
    final visualState = resolveConnectionVisualState(
      vpn,
      ref.read(vpnStateProvider.notifier).recentTransitions,
    );
    final now = useState(DateTime.now());

    useEffect(() {
      Timer? timer;
      if (vpn.status == VpnStatus.connected && vpn.lastTunnelStartAt != null) {
        timer = Timer.periodic(
          const Duration(seconds: 1),
          (_) => now.value = DateTime.now(),
        );
      }
      return timer?.cancel;
    }, [vpn.status, vpn.lastTunnelStartAt]);

    final timerLabel =
        vpn.status == VpnStatus.connected && vpn.lastTunnelStartAt != null
            ? formatDurationClock(now.value.difference(vpn.lastTunnelStartAt!))
            : '00:00:00';
    final locationLabel =
        selectedServer?.name ?? selectedServer?.country ?? 'Automatic routing';
    final addressLabel = visualState == ConnectionVisualState.connected
        ? (selectedServer?.publicIp ?? 'Secure route active')
        : 'Not assigned';
    final protocolLabel =
        vpnProtocolLabel(vpn.effectiveProtocol ?? vpn.protocol);
    final statusLabel = _statusLabel(visualState, vpn);
    final statusDetail = _statusDetail(visualState, vpn, selectedServer?.name);
    final buttonHeadline = switch (visualState) {
      ConnectionVisualState.connected => 'Disconnect',
      ConnectionVisualState.connecting => 'Connecting',
      ConnectionVisualState.reconnecting => 'Reconnecting',
      ConnectionVisualState.disconnecting => 'Disconnecting',
      ConnectionVisualState.error => 'Retry',
      ConnectionVisualState.disconnected => 'Connect',
    };
    final buttonCaption = switch (visualState) {
      ConnectionVisualState.connected => 'Protected via $locationLabel',
      ConnectionVisualState.connecting =>
        'Provisioning profile and bringing up the tunnel',
      ConnectionVisualState.reconnecting => 'Recovering your secure route',
      ConnectionVisualState.disconnecting => 'Removing the active secure route',
      ConnectionVisualState.error =>
        vpn.errorMessage ?? 'Tap to retry the secure connection',
      ConnectionVisualState.disconnected => 'Secure your session with one tap',
    };

    return PageFrame(
      eyebrow: 'Home',
      title: 'Secure network control',
      subtitle:
          'A central connection surface with live tunnel status, usage, and quick navigation.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          GlassPanel(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Current location',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: SecureWaveSpacing.spaceXS),
                      Text(
                        locationLabel,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/servers'),
                  icon: const Icon(Icons.public_rounded),
                  label: const Text('Change server'),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.03),
          const SizedBox(height: SecureWaveSpacing.spaceMD),
          Center(
            child: ConnectButton(
              visualState: visualState,
              headline: buttonHeadline,
              caption: buttonCaption,
              onPressed: _buttonAction(ref, visualState),
              diameter: 332,
            ),
          ).animate().fadeIn(duration: 260.ms).scaleXY(begin: 0.98),
          const SizedBox(height: SecureWaveSpacing.spaceMD),
          ConnectionCard(
            statusLabel: statusLabel,
            statusDetail: statusDetail,
            statusColor: StatusIndicator.colorFor(visualState),
            statusIcon: StatusIndicator.iconFor(visualState),
            locationLabel: locationLabel,
            protocolLabel: protocolLabel,
            timerLabel: timerLabel,
            addressLabel: addressLabel,
          ).animate().fadeIn(duration: 280.ms).slideY(begin: 0.03),
          const SizedBox(height: SecureWaveSpacing.spaceMD),
          const TrafficStatsCard()
              .animate()
              .fadeIn(duration: 300.ms, delay: 40.ms)
              .slideY(begin: 0.03),
          const SizedBox(height: SecureWaveSpacing.spaceSM),
          const UsageMeter()
              .animate()
              .fadeIn(duration: 320.ms, delay: 80.ms)
              .slideY(begin: 0.03),
          const SizedBox(height: SecureWaveSpacing.spaceSM),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Quick actions',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: SecureWaveSpacing.spaceSM),
                Wrap(
                  spacing: SecureWaveSpacing.spaceSM,
                  runSpacing: SecureWaveSpacing.spaceSM,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: () => context.go('/servers'),
                      icon: const Icon(Icons.public_rounded),
                      label: const Text('Change server'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/settings'),
                      icon: const Icon(Icons.bolt_rounded),
                      label: Text('Protocol: $protocolLabel'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/settings'),
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Settings'),
                    ),
                  ],
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 340.ms, delay: 120.ms)
              .slideY(begin: 0.03),
        ],
      ),
    );
  }

  VoidCallback? _buttonAction(
    WidgetRef ref,
    ConnectionVisualState visualState,
  ) {
    final notifier = ref.read(vpnStateProvider.notifier);
    return switch (visualState) {
      ConnectionVisualState.connected => notifier.disconnect,
      ConnectionVisualState.connecting ||
      ConnectionVisualState.reconnecting ||
      ConnectionVisualState.disconnecting =>
        null,
      ConnectionVisualState.error ||
      ConnectionVisualState.disconnected =>
        notifier.connect,
    };
  }

  String _statusLabel(ConnectionVisualState visualState, VpnState vpn) {
    return switch (visualState) {
      ConnectionVisualState.connected => 'Connected',
      ConnectionVisualState.connecting => 'Connecting',
      ConnectionVisualState.reconnecting => 'Reconnecting',
      ConnectionVisualState.disconnecting => 'Disconnecting',
      ConnectionVisualState.error => vpn.statusText(),
      ConnectionVisualState.disconnected => 'Disconnected',
    };
  }

  String _statusDetail(
    ConnectionVisualState visualState,
    VpnState vpn,
    String? locationName,
  ) {
    return switch (visualState) {
      ConnectionVisualState.connected => locationName == null
          ? 'Secure route active.'
          : 'Secure route active via $locationName.',
      ConnectionVisualState.connecting =>
        'Control plane checks and handshake validation are in progress.',
      ConnectionVisualState.reconnecting =>
        'Restoring service after a route interruption.',
      ConnectionVisualState.disconnecting =>
        'Gracefully removing the current secure route.',
      ConnectionVisualState.error =>
        vpn.errorMessage ?? 'Diagnostics can help identify the failure point.',
      ConnectionVisualState.disconnected => locationName == null
          ? 'No secure route is active.'
          : 'Ready to connect through $locationName.',
    };
  }
}

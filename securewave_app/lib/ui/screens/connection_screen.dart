import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/state/vpn_state.dart';
import '../components/connect_button.dart';
import '../components/status_indicator.dart';
import '../layout/page_frame.dart';
import '../widgets/glass_panel.dart';
import '../widgets/securewave_motion_art.dart';
import '../widgets/vpn_ui_bindings.dart';

class ConnectionScreen extends HookConsumerWidget {
  const ConnectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnStateProvider);
    final notifier = ref.read(vpnStateProvider.notifier);
    final transitions = notifier.recentTransitions.reversed.take(8).toList();
    final visualState =
        resolveConnectionVisualState(vpn, notifier.recentTransitions);
    final statusLabel = switch (visualState) {
      ConnectionVisualState.connected => 'CONNECTED',
      ConnectionVisualState.connecting => 'CONNECTING',
      ConnectionVisualState.reconnecting => 'RECONNECTING',
      ConnectionVisualState.disconnecting => 'DISCONNECTING',
      ConnectionVisualState.error => 'ERROR',
      ConnectionVisualState.disconnected => 'DISCONNECTED',
    };

    return PageFrame(
      eyebrow: 'Connection',
      title: 'State machine view',
      subtitle:
          'Animated tunnel lifecycle surface for connect, recover, and failure states without touching control-plane logic.',
      child: Column(
        children: <Widget>[
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Stack(
                  children: <Widget>[
                    Container(
                      height: 180,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.22),
                      ),
                    ),
                    const SizedBox(
                      height: 180,
                      child: SecureWaveMotionArt(opacity: 0.12),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          StatusIndicator(
                            label: vpn.statusText(includeEllipsis: true),
                            detail: statusLabel,
                            color: StatusIndicator.colorFor(visualState),
                            icon: StatusIndicator.iconFor(visualState),
                            emphasized: true,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            _headline(visualState),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            vpn.errorMessage ?? _detail(visualState),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Center(
                  child: ConnectButton(
                    visualState: visualState,
                    headline: _buttonHeadline(visualState),
                    caption: _detail(visualState),
                    onPressed: switch (visualState) {
                      ConnectionVisualState.connected => notifier.disconnect,
                      ConnectionVisualState.connecting ||
                      ConnectionVisualState.reconnecting ||
                      ConnectionVisualState.disconnecting =>
                        null,
                      ConnectionVisualState.error ||
                      ConnectionVisualState.disconnected =>
                        notifier.connect,
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: switch (visualState) {
                        ConnectionVisualState.connected => () async {
                            await notifier.disconnect();
                            await notifier.connect();
                          },
                        ConnectionVisualState.connecting ||
                        ConnectionVisualState.reconnecting ||
                        ConnectionVisualState.disconnecting =>
                          null,
                        ConnectionVisualState.error ||
                        ConnectionVisualState.disconnected =>
                          notifier.connect,
                      },
                      icon: const Icon(Icons.autorenew_rounded),
                      label: const Text('Reconnect'),
                    ),
                    OutlinedButton.icon(
                      onPressed: switch (visualState) {
                        ConnectionVisualState.connected => notifier.disconnect,
                        ConnectionVisualState.connecting ||
                        ConnectionVisualState.reconnecting =>
                          notifier.disconnect,
                        _ => null,
                      },
                      icon: const Icon(Icons.power_settings_new_rounded),
                      label: const Text('Disconnect'),
                    ),
                  ],
                ),
              ],
            ),
          ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.03),
          const SizedBox(height: 20),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Connection stages',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: ConnectionVisualState.values
                      .where(
                        (state) => state != ConnectionVisualState.disconnecting,
                      )
                      .map(
                        (state) => _StateNode(
                          label: switch (state) {
                            ConnectionVisualState.connected => 'CONNECTED',
                            ConnectionVisualState.connecting => 'CONNECTING',
                            ConnectionVisualState.reconnecting =>
                              'RECONNECTING',
                            ConnectionVisualState.error => 'ERROR',
                            ConnectionVisualState.disconnected =>
                              'DISCONNECTED',
                            ConnectionVisualState.disconnecting =>
                              'DISCONNECTING',
                          },
                          active: state == visualState ||
                              (visualState ==
                                      ConnectionVisualState.disconnecting &&
                                  state == ConnectionVisualState.disconnected),
                          color: StatusIndicator.colorFor(state),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 240.ms, delay: 40.ms)
              .slideY(begin: 0.03),
          const SizedBox(height: 16),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Recent transitions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                if (transitions.isEmpty)
                  Text(
                    'No state transitions recorded yet.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  ...transitions.map(
                    (record) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '${record.from.name} → ${record.to.name}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(
                            record.trigger.name,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: 260.ms, delay: 80.ms)
              .slideY(begin: 0.03),
        ],
      ),
    );
  }

  String _buttonHeadline(ConnectionVisualState visualState) {
    return switch (visualState) {
      ConnectionVisualState.connected => 'Disconnect',
      ConnectionVisualState.connecting => 'Connecting',
      ConnectionVisualState.reconnecting => 'Reconnecting',
      ConnectionVisualState.disconnecting => 'Disconnecting',
      ConnectionVisualState.error => 'Retry',
      ConnectionVisualState.disconnected => 'Connect',
    };
  }

  String _headline(ConnectionVisualState visualState) {
    return switch (visualState) {
      ConnectionVisualState.connected => 'Secure route active',
      ConnectionVisualState.connecting => 'Establishing a new secure route',
      ConnectionVisualState.reconnecting => 'Recovering connectivity',
      ConnectionVisualState.disconnecting => 'Shutting down tunnel',
      ConnectionVisualState.error => 'Tunnel requires attention',
      ConnectionVisualState.disconnected => 'Ready to connect',
    };
  }

  String _detail(ConnectionVisualState visualState) {
    return switch (visualState) {
      ConnectionVisualState.connected =>
        'Traffic is currently pinned to the active VPN interface.',
      ConnectionVisualState.connecting =>
        'Fetching a profile, preparing the interface, and validating the handshake.',
      ConnectionVisualState.reconnecting =>
        'Reusing your desired state to restore protection quickly.',
      ConnectionVisualState.disconnecting =>
        'Removing interface routes and finalizing tunnel metrics.',
      ConnectionVisualState.error =>
        'Retry the route or inspect diagnostics before reconnecting.',
      ConnectionVisualState.disconnected =>
        'No secure route is active on this device.',
    };
  }
}

class _StateNode extends StatelessWidget {
  const _StateNode({
    required this.label,
    required this.active,
    required this.color,
  });

  final String label;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: active ? color.withValues(alpha: 0.14) : Colors.transparent,
        border: Border.all(
          color: active
              ? color.withValues(alpha: 0.36)
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.24),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: active ? color : Theme.of(context).colorScheme.onSurface,
            ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/widgets/vpn_ui_bindings.dart';
import '../components/connect_button.dart';
import '../components/status_indicator.dart';
import '../components/traffic_stats_card.dart';
import '../components/server_card.dart';

/// Main dashboard / home screen.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final visualState = resolveConnectionVisualState(vpnState);
    final selectedServer = ref.watch(selectedServerProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pagePadding,
            vertical: AppSpacing.space4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SecureWave',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                  ),
                  StatusIndicator(visualState: visualState),
                ],
              ),
              const SizedBox(height: AppSpacing.space7),

              // ── Connect button ────────────────────────────────────────
              Center(
                child: ConnectButton(
                  visualState: visualState,
                  onTap: () {
                    final notifier = ref.read(vpnStateProvider.notifier);
                    if (visualState == ConnectionVisualState.connected ||
                        visualState == ConnectionVisualState.connecting) {
                      notifier.disconnect();
                    } else {
                      notifier.connect();
                    }
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.space6),

              // ── Traffic stats ─────────────────────────────────────────
              TrafficStatsCard(vpnState: vpnState),
              const SizedBox(height: AppSpacing.space4),

              // ── Selected server ───────────────────────────────────────
              if (selectedServer != null) ...[
                ServerCard(
                  server: selectedServer,
                  isSelected: true,
                  onTap: null,
                ),
              ] else ...[
                _NoServerCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NoServerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Row(
          children: [
            const Icon(Icons.public_rounded, color: AppColors.inkSoft),
            const SizedBox(width: AppSpacing.space3),
            Text(
              'No server selected',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.inkSoft,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

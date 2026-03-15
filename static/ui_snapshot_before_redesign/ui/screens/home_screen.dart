import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/vpn_state.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/widgets/vpn_ui_bindings.dart';
import '../components/connect_button.dart';
import '../components/status_display.dart';
import '../components/traffic_stats_card.dart';
import '../components/server_location_card.dart';

/// Main dashboard.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final visualState = resolveConnectionVisualState(vpnState);
    final selectedServer = ref.watch(selectedServerProvider);
    final isConnected = visualState == ConnectionVisualState.connected;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isConnected
              ? AppColors.darkSurfaceMuted
              : cs.surfaceContainerLowest,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pagePadding,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                    maxWidth: AppSpacing.contentMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.space5),

                    // ── Header ─────────────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'Secure',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      color: AppColors.darkInk,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                    ),
                              ),
                              TextSpan(
                                text: 'Wave',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      color: AppColors.primaryBright,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.notifications_none_rounded),
                          color: AppColors.inkSoft,
                          onPressed: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.space7),

                    // ── Connect button ──────────────────────────────────────
                    Center(
                      child: ConnectButton(
                        visualState: visualState,
                        onTap: () {
                          final notifier =
                              ref.read(vpnStateProvider.notifier);
                          if (isConnected ||
                              visualState ==
                                  ConnectionVisualState.connecting) {
                            notifier.disconnect();
                          } else {
                            notifier.connect();
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space5),

                    // ── Status display ──────────────────────────────────────
                    const Center(child: StatusDisplay()),
                    const SizedBox(height: AppSpacing.space6),

                    // ── Traffic stats ───────────────────────────────────────
                    AnimatedOpacity(
                      opacity: isConnected ? 1.0 : 0.5,
                      duration: const Duration(milliseconds: 400),
                      child: TrafficStatsCard(vpnState: vpnState),
                    ),
                    const SizedBox(height: AppSpacing.space4),

                    // ── Server selector ─────────────────────────────────────
                    _ServerRow(
                      selectedServer: selectedServer,
                      onChangeTap: () => context.go('/servers'),
                    ),
                    const SizedBox(height: AppSpacing.space6),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({required this.selectedServer, required this.onChangeTap});

  final dynamic selectedServer;
  final VoidCallback onChangeTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (selectedServer != null)
          Expanded(
            child: ServerLocationCard(server: selectedServer),
          )
        else
          Expanded(
            child: _EmptyServerChip(),
          ),
        const SizedBox(width: AppSpacing.space3),
        _ChangeButton(onTap: onChangeTap),
      ],
    );
  }
}

class _EmptyServerChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space4,
        vertical: AppSpacing.space3,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.public_rounded,
              size: AppSpacing.iconS, color: cs.onSurfaceVariant),
          const SizedBox(width: AppSpacing.space2),
          Text(
            'No server selected',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _ChangeButton extends StatelessWidget {
  const _ChangeButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
        foregroundColor: AppColors.primaryBright,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space3,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
        ),
      ),
      child: const Text('Change'),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/buttons/primary_button.dart';
import '../../widgets/cards/info_card.dart';
import '../../widgets/buttons/secondary_button.dart';
import '../../widgets/layouts/content_layout.dart';
import '../../widgets/layouts/section_header.dart';
import '../../widgets/layouts/responsive_wrap.dart';
import '../../widgets/loaders/inline_banner.dart';
import 'vpn_test_controller.dart';

class VpnTestPage extends ConsumerWidget {
  const VpnTestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(vpnTestControllerProvider);

    return SafeArea(
      child: ContentLayout(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const SectionHeader(
              title: 'Run diagnostics',
              subtitle: 'Latency, throughput, leak checks.',
            ),
            const SizedBox(height: 20),
            LinearProgressIndicator(value: state.isRunning ? state.progress : 0),
            const SizedBox(height: 16),
            PrimaryButton(
              label: state.isRunning ? 'Running...' : 'Start test',
              isLoading: state.isRunning,
              onPressed: state.isRunning
                  ? null
                  : () async {
                      await ref.read(vpnTestControllerProvider.notifier).runTest();
                      if (context.mounted) context.go('/tests/results');
                    },
            ),
            const SizedBox(height: 12),
            ResponsiveWrap(
              minItemWidth: 180,
              children: [
                SecondaryButton(
                  label: 'VPN status',
                  icon: Icons.shield,
                  onPressed: () => context.go('/vpn'),
                ),
                SecondaryButton(
                  label: 'Back to dashboard',
                  icon: Icons.dashboard,
                  onPressed: () => context.go('/dashboard'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const InlineBanner(
              message: 'Keep the VPN connected in the SecureWave app for accurate results.',
              color: Color(0xFF38BDF8),
            ),
            const SizedBox(height: 16),
            const InfoCard(
              title: 'What this checks',
              subtitle: 'Latency, throughput, DNS leak protection, IPv6 leak protection.',
            ),
          ],
        ),
      ),
    );
  }
}

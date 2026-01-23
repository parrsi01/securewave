import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/cards/info_card.dart';
import '../../widgets/buttons/secondary_button.dart';
import '../../widgets/layouts/content_layout.dart';
import '../../widgets/layouts/section_header.dart';
import '../../widgets/layouts/responsive_wrap.dart';
import '../../widgets/loaders/inline_banner.dart';
import 'vpn_test_controller.dart';

class VpnTestResultsPage extends ConsumerWidget {
  const VpnTestResultsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(vpnTestControllerProvider);
    final result = state.result;

    return SafeArea(
      child: ContentLayout(
        child: result == null
            ? const Center(child: Text('Run diagnostics to view results.'))
            : ListView(
                padding: EdgeInsets.zero,
                children: [
                  const SectionHeader(
                    title: 'Test summary',
                    subtitle: 'Connection performance at a glance.',
                  ),
                  const SizedBox(height: 16),
                  InlineBanner(
                    message: result['status'] == 'PASSED'
                        ? 'Connection performance is within expected range.'
                        : 'Connection performance needs attention. Review the details below.',
                    color: result['status'] == 'PASSED' ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  ),
                  const SizedBox(height: 12),
                  ResponsiveWrap(
                    minItemWidth: 180,
                    children: [
                      SecondaryButton(
                        label: 'Run again',
                        icon: Icons.refresh,
                        onPressed: () => context.go('/tests'),
                      ),
                      SecondaryButton(
                        label: 'VPN status',
                        icon: Icons.shield,
                        onPressed: () => context.go('/vpn'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InfoCard(
                    title: 'Overall score',
                    subtitle: '${result['score']} / 100 • ${result['status']}',
                  ),
                  const SizedBox(height: 12),
                  InfoCard(
                    title: 'Latency delta',
                    subtitle: '+${result['latency_delta']} ms',
                  ),
                  const SizedBox(height: 12),
                  InfoCard(
                    title: 'Throughput',
                    subtitle: '${result['throughput']}% of baseline speed',
                  ),
                  const SizedBox(height: 12),
                  InfoCard(
                    title: 'Leak checks',
                    subtitle:
                        'DNS: ${result['dns_leak'] ? 'Leak detected' : 'Secure'} • IPv6: ${result['ipv6_leak'] ? 'Leak detected' : 'Secure'}',
                  ),
                  const SizedBox(height: 12),
                  const InfoCard(
                    title: 'Recommended next step',
                    subtitle: 'If you see a failure, reconnect and rerun the test.',
                  ),
                ],
              ),
      ),
    );
  }
}

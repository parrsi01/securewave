import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/cards/info_card.dart';
import '../../widgets/layouts/section_header.dart';
import 'vpn_test_controller.dart';

class VpnTestResultsPage extends ConsumerWidget {
  const VpnTestResultsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(vpnTestControllerProvider);
    final result = state.result;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: result == null
            ? const Center(child: Text('Run a test to view results.'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                    title: 'SecureWave test summary',
                    subtitle: 'A quick view of your tunnel performance.',
                  ),
                  const SizedBox(height: 16),
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
                    subtitle: '${result['throughput']}% of baseline',
                  ),
                  const SizedBox(height: 12),
                  InfoCard(
                    title: 'Leak checks',
                    subtitle:
                        'DNS: ${result['dns_leak'] ? 'Leak detected' : 'Secure'} • IPv6: ${result['ipv6_leak'] ? 'Leak detected' : 'Secure'}',
                  ),
                ],
              ),
      ),
    );
  }
}

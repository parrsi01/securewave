import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/buttons/primary_button.dart';
import '../../widgets/layouts/content_layout.dart';
import '../../widgets/layouts/section_header.dart';
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
              title: 'Run SecureWave diagnostics',
              subtitle: 'Measures latency, throughput, and leak protection.',
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
            const InlineBanner(
              message: 'Keep the VPN connected in the SecureWave app for accurate results.',
              color: Color(0xFF38BDF8),
            ),
          ],
        ),
      ),
    );
  }
}

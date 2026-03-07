import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/vpn_state.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import '../../ui/widgets/ui_helpers.dart';
import 'traffic_stats_card.dart';

/// Riverpod-wired metrics widget — reads [vpnStateProvider] and renders
/// a [TrafficStatsCard].
class MetricsDisplay extends ConsumerWidget {
  const MetricsDisplay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    return TrafficStatsCard(vpnState: vpnState);
  }
}

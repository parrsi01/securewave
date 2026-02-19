import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vpn_status.dart';
import '../../../core/state/vpn_state.dart';
import '../../../ui/design/app_animations.dart';
import '../../../ui/design/app_colors.dart';
import '../../../ui/design/app_spacing.dart';

class StatusDisplay extends ConsumerStatefulWidget {
  const StatusDisplay({super.key});

  @override
  ConsumerState<StatusDisplay> createState() => _StatusDisplayState();
}

class _StatusDisplayState extends ConsumerState<StatusDisplay> {
  Timer? _timer;
  DateTime? _connectedSince;
  Duration _elapsed = Duration.zero;

  void _syncTimer(VpnStatus status) {
    if (status == VpnStatus.connected) {
      _connectedSince ??= DateTime.now();
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _connectedSince != null) {
          setState(() => _elapsed = DateTime.now().difference(_connectedSince!));
        }
      });
    } else {
      _timer?.cancel();
      _timer = null;
      _connectedSince = null;
      _elapsed = Duration.zero;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final vpn = ref.watch(vpnStateProvider);
    _syncTimer(vpn.status);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: AppAnimations.durationNormal,
          child: Text(
            vpn.statusText(includeEllipsis: true),
            key: ValueKey(vpn.status),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: vpn.statusColor,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        if (vpn.status == VpnStatus.connected) ...[
          const SizedBox(height: AppSpacing.space1),
          Text(
            _fmt(_elapsed),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.inkMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
        if (vpn.status == VpnStatus.error && vpn.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.space2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space5),
            child: Text(
              vpn.errorMessage!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }
}

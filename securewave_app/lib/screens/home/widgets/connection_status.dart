import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/vpn_status.dart';
import '../../../core/state/vpn_state.dart';
import '../../../ui/design/app_colors.dart';
import '../../../ui/design/app_spacing.dart';

class ConnectionStatus extends ConsumerStatefulWidget {
  const ConnectionStatus({super.key});

  @override
  ConsumerState<ConnectionStatus> createState() => _ConnectionStatusState();
}

class _ConnectionStatusState extends ConsumerState<ConnectionStatus> {
  DateTime? _connectedAt;
  Timer? _durationTimer;
  String _durationText = '';

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _connectedAt = DateTime.now();
    _updateDurationText();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateDurationText();
    });
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _connectedAt = null;
    _durationText = '';
  }

  void _updateDurationText() {
    if (_connectedAt == null) return;
    final elapsed = DateTime.now().difference(_connectedAt!);
    final hours = elapsed.inHours.toString().padLeft(2, '0');
    final minutes = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    if (mounted) {
      setState(() {
        _durationText = '$hours:$minutes:$seconds';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vpn = ref.watch(vpnStateProvider);

    // Track connection state transitions for the duration timer.
    ref.listen<VpnState>(vpnStateProvider, (previous, next) {
      if (next.status == VpnStatus.connected &&
          previous?.status != VpnStatus.connected) {
        _startDurationTimer();
      } else if (next.status != VpnStatus.connected &&
          previous?.status == VpnStatus.connected) {
        _stopDurationTimer();
      }
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          vpn.statusText(includeEllipsis: true),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: vpn.statusColor,
          ),
        ),
        if (vpn.status == VpnStatus.connected && _durationText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.space1),
            child: Text(
              _durationText,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.inkMuted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        if (vpn.status == VpnStatus.error && vpn.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.space2,
              left: AppSpacing.space4,
              right: AppSpacing.space4,
            ),
            child: Text(
              vpn.errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.inkSoft,
              ),
            ),
          ),
      ],
    );
  }
}

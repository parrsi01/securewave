import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/state/app_state.dart';
import '../../../core/state/vpn_state.dart';
import '../../../ui/design/app_animations.dart';
import '../../../ui/design/app_colors.dart';
import '../../../ui/design/app_spacing.dart';

class ServerPill extends ConsumerWidget {
  const ServerPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnStateProvider);
    final servers = ref.watch(serversProvider);
    final id = vpn.selectedServerId;

    String label = 'Auto (Fastest)';
    if (id != null) {
      servers.whenData((list) {
        final m = list.where((s) => s.id == id);
        if (m.isNotEmpty) label = m.first.name;
      });
    }

    return Semantics(
      button: true,
      label: 'Selected server: $label. Double tap to change.',
      child: GestureDetector(
        onTap: () => context.go('/locations'),
        child: AnimatedContainer(
          duration: AppAnimations.durationFast,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            border: Border.all(color: vpn.statusColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.public_rounded, size: 16, color: AppColors.inkMuted),
              const SizedBox(width: AppSpacing.space2),
              Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(width: AppSpacing.space2),
              Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/state/vpn_state.dart';
import '../../../ui/design/app_colors.dart';
import '../../../ui/design/app_spacing.dart';

class QuickLocationSelector extends ConsumerWidget {
  const QuickLocationSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnStateProvider);
    final serverId = vpn.selectedServerId;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
        side: const BorderSide(color: AppColors.border),
      ),
      color: AppColors.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
        onTap: () => context.go('/locations'),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space4,
            vertical: AppSpacing.space3,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.public,
                size: 22,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: Text(
                  serverId ?? 'Auto - Best Location',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 22,
                color: AppColors.inkSoft,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

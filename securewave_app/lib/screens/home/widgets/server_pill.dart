import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/state/app_state.dart';
import '../../../core/state/vpn_state.dart';
import '../../../ui/design/app_animations.dart';
import '../../../ui/design/app_colors.dart';
import '../../../ui/design/app_spacing.dart';

/// Server pill — v2.
///
/// Elegant pill button showing the selected server.
/// Tinted with VPN status color for at-a-glance status feedback.
class ServerPill extends ConsumerWidget {
  const ServerPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId   = ref.watch(vpnStateProvider.select((s) => s.selectedServerId));
    final statusColor  = ref.watch(vpnStateProvider.select((s) => s.statusColor));
    final servers      = ref.watch(serversProvider);
    final isDark       = Theme.of(context).brightness == Brightness.dark;

    String label = 'Auto (Fastest)';

    if (selectedId != null) {
      servers.maybeWhen(
        data: (list) {
          for (final server in list) {
            if (server.id == selectedId) {
              label = server.name;
              break;
            }
          }
        },
        orElse: () {},
      );
    }

    return Semantics(
      button: true,
      label: 'Selected server: $label. Tap to change.',
      child: GestureDetector(
        onTap: () => context.go('/locations'),
        child: AnimatedContainer(
          duration: AppAnimations.durationFast,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space4,
            vertical: AppSpacing.space3,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            color: isDark
                ? AppColors.darkSurface.withValues(alpha: 0.80)
                : AppColors.surface.withValues(alpha: 0.90),
            border: Border.all(
              color: statusColor.withValues(alpha: 0.30),
              width: 1,
            ),
            boxShadow: isDark
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))]
                : [BoxShadow(color: AppColors.ink.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.public_rounded,
                size: AppSpacing.iconXS,
                color: statusColor,
              ),
              const SizedBox(width: AppSpacing.space2),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: AppSpacing.space2),
              Icon(
                Icons.expand_more_rounded,
                size: AppSpacing.iconXS,
                color: isDark ? AppColors.darkInkSoft : AppColors.inkSoft,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

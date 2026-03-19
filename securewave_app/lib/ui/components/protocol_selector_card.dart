import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/vpn_protocol.dart';
import '../../core/models/vpn_protocol_catalog.dart';
import '../../core/models/vpn_status.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../design/app_colors.dart';
import '../design/app_spacing.dart';
import '../widgets/glass_panel.dart';

class ProtocolSelectorCard extends ConsumerWidget {
  const ProtocolSelectorCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final catalogAsync = ref.watch(vpnProtocolCatalogProvider);
    final activeTunnel = vpnState.status == VpnStatus.connected ||
        vpnState.status == VpnStatus.degraded ||
        vpnState.status == VpnStatus.connecting ||
        vpnState.status == VpnStatus.verifying ||
        vpnState.status == VpnStatus.reconnecting ||
        vpnState.status == VpnStatus.disconnecting;

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Protocol',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space3,
                  vertical: AppSpacing.space1,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Text(
                  vpnProtocolLabel(vpnState.protocol),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            activeTunnel
                ? 'Changing protocol updates the next reconnect cycle.'
                : 'Choose the best tunnel mode for this device.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.space4),
          catalogAsync.when(
            loading: () => Wrap(
              spacing: AppSpacing.space2,
              runSpacing: AppSpacing.space2,
              children: List.generate(
                4,
                (index) => Container(
                  width: 110,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                ),
              ),
            ),
            error: (error, _) => _ProtocolError(message: error.toString()),
            data: (catalog) {
              final entries = _entriesFor(catalog);
              return Wrap(
                spacing: AppSpacing.space2,
                runSpacing: AppSpacing.space2,
                children: entries.map((entry) {
                  final selected = vpnState.protocol == entry.protocol;
                  final enabled =
                      entry.protocol == VpnProtocol.auto || entry.isAvailable;
                  final helpText =
                      enabled ? null : (entry.reason ?? 'Unavailable');
                  return Tooltip(
                    message: helpText ?? vpnProtocolLabel(entry.protocol),
                    child: ChoiceChip(
                      label: Text(vpnProtocolLabel(entry.protocol)),
                      selected: selected,
                      selectedColor:
                          AppColors.primaryBright.withValues(alpha: 0.18),
                      side: BorderSide(
                        color: selected
                            ? AppColors.primaryBright
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                      labelStyle: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: enabled
                                ? null
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                          ),
                      avatar: _protocolAvatar(entry, selected),
                      onSelected: enabled
                          ? (_) => ref
                              .read(vpnStateProvider.notifier)
                              .selectProtocol(entry.protocol)
                          : null,
                    ),
                  );
                }).toList(),
              );
            },
          ),
          if (vpnState.protocolMessage != null &&
              vpnState.protocolMessage!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.space3),
            Text(
              vpnState.protocolMessage!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.warning,
                  ),
            ),
          ],
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 320.ms)
        .slideY(begin: 0.06, end: 0, curve: Curves.easeOutCubic);
  }

  List<VpnProtocolCatalogEntry> _entriesFor(VpnProtocolCatalog catalog) {
    final out = <VpnProtocolCatalogEntry>[
      const VpnProtocolCatalogEntry(
        protocol: VpnProtocol.auto,
        enabled: true,
        serverEnabled: true,
        planEnabled: true,
        platformSupported: true,
        reason: 'Automatically choose the best available protocol.',
      ),
      ...catalog.protocols,
    ];

    final existing = out.map((entry) => entry.protocol).toSet();
    for (final protocol in VpnProtocol.values) {
      if (existing.contains(protocol) || protocol == VpnProtocol.auto) {
        continue;
      }
      out.add(
        VpnProtocolCatalogEntry(
          protocol: protocol,
          enabled: false,
          serverEnabled: false,
          planEnabled: false,
          platformSupported: false,
          reason: 'Unavailable for this device or plan.',
        ),
      );
    }
    return out;
  }

  Widget _protocolAvatar(VpnProtocolCatalogEntry entry, bool selected) {
    if (entry.protocol == VpnProtocol.auto) {
      return Icon(
        Icons.auto_awesome_rounded,
        size: AppSpacing.iconS,
        color: selected ? AppColors.primaryBright : null,
      );
    }
    if (entry.isAvailable) {
      return Icon(
        Icons.shield_moon_rounded,
        size: AppSpacing.iconS,
        color: selected ? AppColors.primaryBright : AppColors.success,
      );
    }
    return const Icon(
      Icons.lock_outline_rounded,
      size: AppSpacing.iconS,
    );
  }
}

class _ProtocolError extends StatelessWidget {
  const _ProtocolError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusL),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
      ),
      child: Text(
        'Protocol catalog unavailable.\n$message',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.warning,
            ),
      ),
    );
  }
}

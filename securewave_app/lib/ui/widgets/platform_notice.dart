import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/app_state.dart';
import '../design/app_colors.dart';
import '../design/app_spacing.dart';

class PlatformNotice extends ConsumerWidget {
  const PlatformNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capsAsync = ref.watch(vpnCapabilitiesProvider);

    // Still loading — hide the notice to avoid false-positive flicker.
    if (!capsAsync.hasValue) return const SizedBox.shrink();

    final caps = capsAsync.value!;

    // Build the list of actionable platform notices.
    final notices = <String>[];

    if (kIsWeb) {
      notices.add('VPN cannot run in the browser. '
          'Download the native app for full VPN functionality.');
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      if (!caps.wireGuard) {
        notices.add(caps.macosEntitlementWarning ??
            'VPN unavailable on this build. Network Extension is not configured.');
      }
    } else if (defaultTargetPlatform == TargetPlatform.linux) {
      if (!caps.linuxWireGuardInstalled) {
        notices.add(caps.wireGuardInstallHint ??
            'WireGuard: install wireguard-tools to enable VPN tunneling:\n'
                '  Ubuntu/Debian: sudo apt-get install wireguard-tools');
      }
      if (!caps.openVpn) {
        notices.add(caps.openVpnInstallHint ??
            'OpenVPN: requires OS helper (OpenVPN client binary). Install OpenVPN and retry.');
      }
      if (!caps.ikev2) {
        notices.add(caps.ikev2InstallHint ??
            'IKEv2/IPsec: requires OS helper (NetworkManager + strongSwan components).');
      }
      if (!caps.linuxElevationAvailable) {
        notices.add(caps.linuxElevationHint ??
            'Administrator prompt helper is unavailable. '
                'Install PolicyKit (pkexec) and ensure a polkit authentication '
                'agent is running, or launch SecureWave as root.');
      }
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      if (!caps.openVpn && caps.openVpnInstallHint != null) {
        notices.add('OpenVPN: ${caps.openVpnInstallHint!}');
      }
      if (!caps.ikev2 && caps.ikev2InstallHint != null) {
        notices.add('IKEv2/IPsec: ${caps.ikev2InstallHint!}');
      }
    } else {
      if (!caps.wireGuard) {
        notices.add('VPN tunnel is not available on this platform or build.');
      }
    }

    if (notices.isEmpty) return const SizedBox.shrink();

    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Platform setup notice. ${notices.join('. ')}',
      child: Card(
        elevation: 0,
        color: AppColors.secondary.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusM),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.info_outline,
                  size: 20,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(width: AppSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Platform requirements',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space1),
                    ...notices.map(
                      (notice) => Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.space1),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.fiber_manual_record,
                                size: 8,
                                color: AppColors.inkMuted,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.space2),
                            Expanded(
                              child: Text(
                                notice,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.inkMuted,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

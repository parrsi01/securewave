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
    final vpnService = ref.watch(vpnServiceProvider);

    // No notice needed if native VPN is available.
    if (vpnService.isNativeAvailable) {
      return const SizedBox.shrink();
    }

    final String message;
    if (kIsWeb) {
      message = 'VPN cannot run in the browser. '
          'Download the native app for full VPN functionality.';
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      message = 'VPN unavailable on this build. '
          'Network Extension is not configured.';
    } else {
      message = 'VPN tunnel is not available on this platform or build.';
    }

    return Card(
      elevation: 0,
      color: AppColors.secondary.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space3),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline,
              size: 20,
              color: AppColors.inkMuted,
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.inkMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

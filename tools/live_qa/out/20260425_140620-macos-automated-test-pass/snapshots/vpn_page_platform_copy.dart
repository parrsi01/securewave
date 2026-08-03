import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:platform_info/platform_info.dart';

import '../../core/models/vpn_status.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_ui_v1.dart';

class VpnPage extends ConsumerWidget {
  const VpnPage({super.key});

  /// Returns a human-readable label for the current platform's VPN capability.
  /// null means fully supported; a String means limited or not configured.
  String? _platformNotice() {
    final os = platform.operatingSystem;
    if (kIsWeb) {
      return 'VPN tunnels cannot run inside a web browser. Download the native app.';
    }
    switch (os) {
      case OperatingSystem.linux:
        return 'Linux VPN uses wg-quick. Install WireGuard tools and allow '
            'the app to run elevated commands when prompted.';
      case OperatingSystem.windows:
        return 'Windows VPN requires WireGuard for Windows (wireguard.exe). '
            'Install it to enable native tunneling.';
      case OperatingSystem.macOS:
        return 'macOS VPN support is coming soon. The app requires additional '
            'Apple approvals before VPN tunnels can be established on Mac.';
      case OperatingSystem.iOS:
      case OperatingSystem.android:
        return null; // Fully supported
      default:
        return 'This platform is not supported for VPN tunnels.';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpnState = ref.watch(vpnStateProvider);
    final servers = ref.watch(serversProvider);
    final vpnService = ref.watch(vpnServiceProvider);

    final serversData = servers.maybeWhen(data: (data) => data, orElse: () => null);
    if (serversData != null && serversData.isNotEmpty && vpnState.selectedServerId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(vpnStateProvider.notifier).selectServer(serversData.first.id);
      });
    }

    final selectedServerLabel = serversData == null || serversData.isEmpty
        ? 'Auto-select'
        : serversData
                .firstWhere(
                  (server) => server.id == vpnState.selectedServerId,
                  orElse: () => serversData.first,
                )
                .name;

    final statusText = switch (vpnState.status) {
      VpnStatus.connected => 'Connected',
      VpnStatus.connecting => 'Connecting',
      VpnStatus.error => 'Needs attention',
      VpnStatus.disconnected => 'Disconnected',
    };

    final statusColor = switch (vpnState.status) {
      VpnStatus.connected => AppUIv1.success,
      VpnStatus.connecting => AppUIv1.accentSun,
      VpnStatus.error => AppUIv1.warning,
      VpnStatus.disconnected => AppUIv1.inkSoft,
    };
    final primaryActionLabel = vpnState.status == VpnStatus.connecting
        ? 'Connecting...'
        : vpnState.status == VpnStatus.connected
            ? 'Disconnect'
            : 'Connect';


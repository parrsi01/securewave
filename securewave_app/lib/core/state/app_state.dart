import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:platform_info/platform_info.dart';

import '../config/runtime_config.dart';
import '../models/server_region.dart';
import '../models/user_plan.dart';
import '../models/vpn_protocol_catalog.dart';
import '../services/auth_session.dart';
import '../services/vpn_service.dart';
import '../vpn/vpn_adapter.dart';
import '../vpn/vpn_factory.dart';
import '../vpn/protocol_capabilities.dart';
import '../../services/api_client.dart';

final vpnServiceProvider = Provider<VpnService>((ref) {
  return ChannelVpnService();
});

final vpnAdapterProvider = Provider<VpnAdapter>((ref) {
  return createVpnAdapter(realService: ref.watch(vpnServiceProvider));
});

const VpnCapabilities _mockVpnCapabilities = VpnCapabilities(
  wireGuard: true,
  openVpn: true,
  ikev2: true,
  windowsThreadSafe: true,
  androidVpnServiceBased: true,
  macosEntitlementReady: true,
  linuxWireGuardInstalled: true,
  linuxElevationAvailable: true,
);

final vpnCapabilitiesProvider = FutureProvider<VpnCapabilities>((ref) async {
  if (isMockVpn) {
    return _mockVpnCapabilities;
  }
  return ref.watch(vpnServiceProvider).getCapabilities();
});

final vpnProtocolCatalogProvider =
    FutureProvider<VpnProtocolCatalog>((ref) async {
  final isAuthenticated = ref.watch(
    authSessionProvider.select((session) => session.isAuthenticated),
  );
  if (!isAuthenticated) {
    return VpnProtocolCatalog(
      userTier: 'free',
      deviceType: ProtocolCapabilityMatrix.currentDeviceType(),
      protocols: const <VpnProtocolCatalogEntry>[],
    );
  }
  final api = ref.watch(apiClientProvider);
  return api.fetchVpnProtocols(
    deviceType: ProtocolCapabilityMatrix.currentDeviceType(),
  );
});

final deviceInfoProvider = Provider<String>((ref) {
  final osName = platform.operatingSystem.name;
  final device = platform.version.isNotEmpty ? platform.version : osName;
  return '$osName • $device';
});

final serversProvider = FutureProvider<List<ServerRegion>>((ref) async {
  final isAuthenticated = ref.watch(
    authSessionProvider.select((session) => session.isAuthenticated),
  );
  if (!isAuthenticated) {
    return const <ServerRegion>[];
  }
  final api = ref.watch(apiClientProvider);
  return api.fetchServers();
});

final userPlanProvider = FutureProvider<UserPlan>((ref) async {
  final isAuthenticated = ref.watch(
    authSessionProvider.select((session) => session.isAuthenticated),
  );
  if (!isAuthenticated) {
    return const UserPlan(
      name: 'Free',
      isPremium: false,
      dataCapGb: 5,
      usedGb: 0,
      dataCapBytes: 5 * 1024 * 1024 * 1024,
      usedBytes: 0,
      speedDownMbps: 25,
      speedUpMbps: 10,
    );
  }
  final api = ref.watch(apiClientProvider);
  return api.fetchUserPlan();
});

final userProfileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final isAuthenticated = ref.watch(
    authSessionProvider.select((session) => session.isAuthenticated),
  );
  if (!isAuthenticated) {
    return const <String, dynamic>{};
  }
  final api = ref.watch(apiClientProvider);
  return api.fetchProfile();
});

final deviceListProvider = FutureProvider<DeviceListResult>((ref) async {
  final isAuthenticated = ref.watch(
    authSessionProvider.select((session) => session.isAuthenticated),
  );
  if (!isAuthenticated) {
    return const DeviceListResult(
      devices: <DeviceInfo>[],
      total: 0,
      limit: 1,
      remaining: 0,
    );
  }
  final api = ref.watch(apiClientProvider);
  return api.listDevices();
});

final favoriteServersProvider =
    StateNotifierProvider<FavoriteServersNotifier, Set<String>>((ref) {
  return FavoriteServersNotifier();
});

class FavoriteServersNotifier extends StateNotifier<Set<String>> {
  FavoriteServersNotifier() : super(<String>{});

  void toggle(String id) {
    final next = Set<String>.from(state);
    if (!next.add(id)) {
      next.remove(id);
    }
    state = next;
  }

  bool isFavorite(String id) => state.contains(id);
}

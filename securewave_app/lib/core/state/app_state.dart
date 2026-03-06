import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:platform_info/platform_info.dart';

import '../models/server_region.dart';
import '../models/user_plan.dart';
import '../models/vpn_protocol_catalog.dart';
import '../services/auth_session.dart';
import '../services/vpn_service.dart';
import '../vpn/protocol_capabilities.dart';
import '../../services/api_client.dart';

final vpnServiceProvider = Provider<VpnService>((ref) {
  // Always use the live native channel bridge. No mock/demo tunnel provider.
  return ChannelVpnService();
});

final vpnCapabilitiesProvider = FutureProvider<VpnCapabilities>((ref) async {
  return ref.watch(vpnServiceProvider).getCapabilities();
});

final vpnProtocolCatalogProvider =
    FutureProvider<VpnProtocolCatalog>((ref) async {
  ref.watch(authSessionProvider.select((session) => session.isAuthenticated));
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
  ref.watch(authSessionProvider.select((session) => session.isAuthenticated));
  final api = ref.watch(apiClientProvider);
  return api.fetchServers();
});

final userPlanProvider = FutureProvider<UserPlan>((ref) async {
  ref.watch(authSessionProvider.select((session) => session.isAuthenticated));
  final api = ref.watch(apiClientProvider);
  return api.fetchUserPlan();
});

final userProfileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(authSessionProvider.select((session) => session.isAuthenticated));
  final api = ref.watch(apiClientProvider);
  return api.fetchProfile();
});

final deviceListProvider = FutureProvider<DeviceListResult>((ref) async {
  ref.watch(authSessionProvider.select((session) => session.isAuthenticated));
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

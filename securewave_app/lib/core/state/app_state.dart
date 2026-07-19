import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:platform_info/platform_info.dart';

import '../models/server_region.dart';
import '../models/protocol_availability.dart';
import '../models/vpn_protocol.dart';
import '../models/user_account.dart';
import '../models/user_plan.dart';
import '../config/app_config.dart';
import '../services/vpn_service.dart';
import '../../services/api_client.dart';

final vpnServiceProvider = Provider<VpnService>((ref) {
  final config = ref.watch(appConfigProvider);
  return ChannelVpnService(
    fallback: MockVpnService(),
    allowFallback: config.useMockApi,
  );
});

final deviceInfoProvider = Provider<String>((ref) {
  final osName = platform.operatingSystem.name;
  final device = platform.version.isNotEmpty ? platform.version : osName;
  return '$osName • $device';
});

final serversProvider = FutureProvider<List<ServerRegion>>((ref) async {
  final api = ref.watch(apiClientProvider);
  return api.fetchServers(deviceType: 'linux');
});

final userPlanProvider = FutureProvider<UserPlan>((ref) async {
  final api = ref.watch(apiClientProvider);
  return api.fetchUserPlan();
});

final currentUserProvider = FutureProvider<UserAccount>((ref) async {
  final api = ref.watch(apiClientProvider);
  return api.fetchCurrentUser();
});

final protocolAvailabilityProvider =
    FutureProvider<Map<VpnProtocol, ProtocolAvailability>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final vpn = ref.watch(vpnServiceProvider);
  final availability = await api.fetchProtocolAvailability(deviceType: 'linux');
  // Prime the native capability state before UI tiles evaluate canConnect.
  // This is a local helper probe only; backend protocol evidence remains the
  // source of truth for whether a server can actually be selected.
  await vpn.refreshProtocolAvailability(VpnProtocol.wireGuard);
  return availability;
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

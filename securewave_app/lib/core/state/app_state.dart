import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:platform_info/platform_info.dart';

import '../models/server_region.dart';
import '../models/user_plan.dart';
import '../services/vpn_service.dart';
import '../../services/api_client.dart';

final vpnServiceProvider = Provider<VpnService>((ref) {
  return ChannelVpnService(fallback: MockVpnService());
});

final deviceInfoProvider = Provider<String>((ref) {
  final osName = platform.operatingSystem.name;
  final device = platform.version.isNotEmpty ? platform.version : osName;
  return '$osName • $device';
});

final serversProvider = FutureProvider<List<ServerRegion>>((ref) async {
  final api = ref.read(apiClientProvider);
  return api.fetchServers();
});

final userPlanProvider = FutureProvider<UserPlan>((ref) async {
  final api = ref.read(apiClientProvider);
  return api.fetchUserPlan();
});

final favoriteServersProvider = StateNotifierProvider<FavoriteServersNotifier, Set<String>>((ref) {
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

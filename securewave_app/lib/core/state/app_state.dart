import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:platform_info/platform_info.dart';

import '../models/server_region.dart';
import '../models/user_account.dart';
import '../models/user_plan.dart';
import '../config/app_config.dart';
import '../services/linux_runtime_setup.dart';
import '../services/vpn_service.dart';
import '../../services/api_client.dart';

final vpnServiceProvider = Provider<VpnService>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.simulateTunnel) {
    return MockVpnService();
  }
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

final linuxRuntimeSetupProvider = Provider<LinuxRuntimeSetupService>((ref) {
  return LinuxRuntimeSetupService();
});

final serversProvider = FutureProvider<List<ServerRegion>>((ref) async {
  final api = ref.watch(apiClientProvider);
  return api.fetchServers();
});

final userPlanProvider = FutureProvider<UserPlan>((ref) async {
  final api = ref.watch(apiClientProvider);
  return api.fetchUserPlan();
});

final currentUserProvider = FutureProvider<UserAccount>((ref) async {
  final api = ref.watch(apiClientProvider);
  return api.fetchCurrentUser();
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

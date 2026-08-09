import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../models/server_region.dart';
import '../models/user_account.dart';
import '../models/user_plan.dart';
import '../services/vpn_service.dart';
import '../../services/api_client.dart';

final vpnServiceProvider = Provider<VpnService>((ref) {
  final config = ref.watch(appConfigProvider);
  return config.demoMode ? DemoVpnService() : ChannelVpnService();
});

final currentUserProvider = FutureProvider<UserAccount>((ref) {
  return ref.watch(apiClientProvider).fetchCurrentUser();
});

final targetProvider = FutureProvider<SecureWaveTarget>((ref) {
  return ref.watch(apiClientProvider).fetchTarget();
});

final serversProvider = FutureProvider<List<ServerRegion>>((ref) {
  return ref.watch(apiClientProvider).fetchServers();
});

final userPlanProvider = FutureProvider<UserPlan>((ref) {
  return ref.watch(apiClientProvider).fetchUserPlan();
});

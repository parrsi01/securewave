import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:platform_info/platform_info.dart';

import 'api_service.dart';
import 'vpn_service.dart';

final vpnServiceProvider = Provider<VpnService>((ref) {
  // Replace VpnServiceMock with a native implementation later.
  return VpnServiceMock();
});

final vpnStatusProvider = StreamProvider<VpnStatus>((ref) {
  final vpnService = ref.watch(vpnServiceProvider);
  return vpnService.statusStream;
});

final deviceInfoProvider = Provider<String>((ref) {
  final osName = platform.operatingSystem.name;
  final device = platform.operatingSystem.version.isNotEmpty
      ? '${platform.operatingSystem.version}'
      : osName;
  return '$osName • $device';
});

final serversProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(apiServiceProvider);
  final response = await api.get('/vpn/servers');
  final data = response.data as List<dynamic>;
  return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

final usageProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final api = ref.read(apiServiceProvider);
  final response = await api.get('/vpn/usage');
  return Map<String, dynamic>.from(response.data as Map);
});

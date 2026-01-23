import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:platform_info/platform_info.dart';

import 'api_service.dart';
import 'vpn_service.dart';

final vpnServiceProvider = Provider<VpnService>((ref) {
  final platform = defaultTargetPlatform;
  if (kIsWeb) {
    return VpnServiceMock();
  }

  if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
    return VpnServiceNative();
  }

  if (platform == TargetPlatform.android) {
    return VpnServiceNative(
      fallback: VpnServiceUnsupported(
        'Android WireGuard integration is in progress. Use a desktop build for live demos.',
      ),
    );
  }

  if (platform == TargetPlatform.windows) {
    return VpnServiceUnsupported(
      'Windows tunnel support is not wired yet. Please use Linux or macOS for live demos.',
    );
  }

  return VpnServiceMock();
});

final vpnStatusProvider = StreamProvider<VpnStatus>((ref) {
  final vpnService = ref.watch(vpnServiceProvider);
  return vpnService.statusStream;
});

final deviceInfoProvider = Provider<String>((ref) {
  final osName = platform.operatingSystem.name;
  final device = platform.version.isNotEmpty ? platform.version : osName;
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

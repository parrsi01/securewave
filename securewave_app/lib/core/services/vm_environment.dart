import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:platform_info/platform_info.dart';

final vmEnvironmentProvider = Provider<VmEnvironment>((ref) {
  return VmEnvironment.detect();
});

class VmEnvironment {
  const VmEnvironment({
    required this.isVirtualMachine,
    required this.safeModeEnabled,
    required this.reason,
    this.hasDockerBridge = false,
    this.likelyHostOnlyNetwork = false,
    this.likelyNatNetwork = false,
    this.multipleTunnelInterfaces = false,
    this.tunnelInterfaces = const <String>[],
    this.defaultRoutePresent = true,
    this.defaultRouteInterface,
  });

  final bool isVirtualMachine;
  final bool safeModeEnabled;
  final String? reason;
  final bool hasDockerBridge;
  final bool likelyHostOnlyNetwork;
  final bool likelyNatNetwork;
  final bool multipleTunnelInterfaces;
  final List<String> tunnelInterfaces;
  final bool defaultRoutePresent;
  final String? defaultRouteInterface;

  bool get isVm => isVirtualMachine;

  factory VmEnvironment.detect() {
    if (kIsWeb) {
      return const VmEnvironment(
        isVirtualMachine: false,
        safeModeEnabled: false,
        reason: null,
      );
    }

    final os = platform.operatingSystem.name.toLowerCase();
    if (os != 'linux') {
      return const VmEnvironment(
        isVirtualMachine: false,
        safeModeEnabled: false,
        reason: null,
      );
    }

    final markers = <String?>[
      _readText('/sys/class/dmi/id/product_name'),
      _readText('/sys/class/dmi/id/sys_vendor'),
      _readText('/sys/class/dmi/id/board_vendor'),
      _readText('/sys/class/dmi/id/product_version'),
    ].whereType<String>().join(' ').toLowerCase();

    final interfaceNames = _listNetworkInterfaces();
    final tunnelInterfaces = interfaceNames
        .where((name) =>
            name.startsWith('wg') ||
            name.startsWith('tun') ||
            name.startsWith('utun') ||
            name.startsWith('sw-wg'))
        .toList(growable: false);
    final hasDockerBridge = interfaceNames.any(
      (name) => name == 'docker0' || name.startsWith('br-') || name == 'veth0',
    );

    final defaultRoute = _readDefaultRoute();
    final gateway = defaultRoute?.gateway ?? '';
    final defaultInterface = defaultRoute?.interfaceName;
    final likelyHostOnlyNetwork = gateway.startsWith('192.168.56.') ||
        interfaceNames.any((name) => name.startsWith('vboxnet'));
    final likelyNatNetwork = gateway.startsWith('10.0.2.') ||
        gateway.startsWith('192.168.122.') ||
        gateway.startsWith('172.16.');
    final isVm = markers.contains('virtualbox') ||
        markers.contains('vmware') ||
        markers.contains('qemu') ||
        markers.contains('kvm') ||
        markers.contains('hyper-v') ||
        markers.contains('parallels') ||
        interfaceNames.any((name) => name.startsWith('vmnet'));

    final details = <String>[
      if (isVm) 'Linux VM detected from DMI or interface markers.',
      if (hasDockerBridge) 'Docker bridge present.',
      if (likelyHostOnlyNetwork) 'Host-only network pattern detected.',
      if (likelyNatNetwork) 'NAT gateway pattern detected.',
      if (tunnelInterfaces.length > 1) 'Multiple tunnel interfaces detected.',
      if (defaultInterface == null) 'Default route missing.',
    ];

    return VmEnvironment(
      isVirtualMachine: isVm,
      safeModeEnabled: isVm,
      reason: details.isEmpty ? null : details.join(' '),
      hasDockerBridge: hasDockerBridge,
      likelyHostOnlyNetwork: likelyHostOnlyNetwork,
      likelyNatNetwork: likelyNatNetwork,
      multipleTunnelInterfaces: tunnelInterfaces.length > 1,
      tunnelInterfaces: tunnelInterfaces,
      defaultRoutePresent: defaultInterface != null,
      defaultRouteInterface: defaultInterface,
    );
  }

  static List<String> _listNetworkInterfaces() {
    try {
      final directory = Directory('/sys/class/net');
      if (!directory.existsSync()) {
        return const <String>[];
      }
      return directory
          .listSync(followLinks: false)
          .map((entry) {
            final segments = entry.uri.pathSegments
                .where((segment) => segment.isNotEmpty)
                .toList(growable: false);
            return segments.isEmpty ? null : segments.last;
          })
          .whereType<String>()
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  static String? _readText(String path) {
    try {
      final value = File(path).readAsStringSync().trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  static _RouteInfo? _readDefaultRoute() {
    try {
      final lines = File('/proc/net/route').readAsLinesSync();
      for (final line in lines.skip(1)) {
        final columns = line.trim().split(RegExp(r'\s+'));
        if (columns.length < 3) {
          continue;
        }
        if (columns[1] == '00000000') {
          return _RouteInfo(
            interfaceName: columns[0],
            gateway: _decodeHexIpv4(columns[2]),
          );
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String _decodeHexIpv4(String hex) {
    if (hex.length != 8) {
      return '';
    }
    final parts = <String>[];
    for (var index = 0; index < 8; index += 2) {
      parts.insert(
        0,
        int.parse(hex.substring(index, index + 2), radix: 16).toString(),
      );
    }
    return parts.join('.');
  }
}

class _RouteInfo {
  const _RouteInfo({required this.interfaceName, required this.gateway});

  final String interfaceName;
  final String gateway;
}

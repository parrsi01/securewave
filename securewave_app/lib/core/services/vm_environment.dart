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
  });

  final bool isVirtualMachine;
  final bool safeModeEnabled;
  final String? reason;

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
    ].whereType<String>().join(' ').toLowerCase();

    final isVm = markers.contains('virtualbox') ||
        markers.contains('vmware') ||
        markers.contains('qemu') ||
        markers.contains('kvm') ||
        markers.contains('hyper-v') ||
        markers.contains('parallels');

    return VmEnvironment(
      isVirtualMachine: isVm,
      safeModeEnabled: isVm,
      reason: isVm ? 'Linux VM detected from DMI markers.' : null,
    );
  }

  static String? _readText(String path) {
    try {
      final value = File(path).readAsStringSync().trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }
}

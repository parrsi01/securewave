import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:platform_info/platform_info.dart';

class LinuxRuntimeInstallState {
  const LinuxRuntimeInstallState({
    required this.installed,
    required this.payloadAvailable,
    required this.installedContract,
    required this.requiredContract,
    required this.message,
    this.supported = true,
  });

  final bool installed;
  final bool payloadAvailable;
  final int installedContract;
  final int requiredContract;
  final String message;
  final bool supported;

  bool get canInstall => supported && !installed && payloadAvailable;

  factory LinuxRuntimeInstallState.fromJson(Map<Object?, Object?> json) {
    int parseInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.round();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    bool parseBool(Object? value) {
      if (value is bool) return value;
      final normalized = value?.toString().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }

    return LinuxRuntimeInstallState(
      installed: parseBool(json['installed']),
      payloadAvailable: parseBool(json['payload_available']),
      installedContract: parseInt(json['installed_contract']),
      requiredContract: parseInt(json['required_contract']),
      message: json['message']?.toString() ?? 'Runtime setup unavailable.',
    );
  }

  static const unsupported = LinuxRuntimeInstallState(
    installed: false,
    payloadAvailable: false,
    installedContract: 0,
    requiredContract: 0,
    message: 'Linux runtime setup is unavailable on this platform.',
    supported: false,
  );
}

class LinuxRuntimeSetupService {
  LinuxRuntimeSetupService({
    MethodChannel channel = const MethodChannel('securewave/vpn'),
  }) : _channel = channel;

  final MethodChannel _channel;

  bool get isSupported {
    if (kIsWeb) return false;
    return platform.operatingSystem.name.toLowerCase() == 'linux';
  }

  Future<LinuxRuntimeInstallState> getInstallState() async {
    if (!isSupported) return LinuxRuntimeInstallState.unsupported;
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'getRuntimeInstallState',
      );
      if (result == null) return LinuxRuntimeInstallState.unsupported;
      return LinuxRuntimeInstallState.fromJson(result);
    } on MissingPluginException {
      return LinuxRuntimeInstallState.unsupported;
    }
  }

  Future<void> installHelper() async {
    if (!isSupported) {
      throw StateError('Linux runtime setup is unavailable on this platform.');
    }
    await _channel.invokeMethod<void>('installRuntimeHelper');
  }
}

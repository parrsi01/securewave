import 'package:flutter/foundation.dart';
import 'package:platform_info/platform_info.dart';
import 'package:uuid/uuid.dart';

import 'secure_storage.dart';

class DeviceIdentity {
  const DeviceIdentity({
    required this.installId,
    required this.name,
    required this.type,
  });

  final String installId;
  final String name;
  final String type; // windows|macos|linux|ios|android|web|other

  static Future<DeviceIdentity> load() async {
    final storage = SecureStorage();

    var installId = await storage.getString(SecureStorage.deviceInstallIdKey);
    if (installId == null || installId.trim().isEmpty) {
      installId = const Uuid().v4();
      await storage.saveString(SecureStorage.deviceInstallIdKey, installId);
    }

    final type = _deviceType();
    var name = await storage.getString(SecureStorage.deviceNameKey);
    if (name == null || name.trim().isEmpty) {
      final suffix =
          installId.replaceAll('-', '').substring(0, 4).toUpperCase();
      name = '${_defaultDeviceName(type)} ($suffix)';
      await storage.saveString(SecureStorage.deviceNameKey, name);
    }

    return DeviceIdentity(installId: installId, name: name, type: type);
  }

  static String _deviceType() {
    if (kIsWeb) return 'web';
    switch (platform.operatingSystem) {
      case OperatingSystem.android:
        return 'android';
      case OperatingSystem.iOS:
        return 'ios';
      case OperatingSystem.macOS:
        return 'macos';
      case OperatingSystem.windows:
        return 'windows';
      case OperatingSystem.linux:
        return 'linux';
      default:
        return 'other';
    }
  }

  static String _defaultDeviceName(String type) {
    switch (type) {
      case 'android':
        return 'Android device';
      case 'ios':
        return 'iPhone/iPad';
      case 'macos':
        return 'Mac';
      case 'windows':
        return 'Windows PC';
      case 'linux':
        return 'Linux device';
      case 'web':
        return 'Web session';
      default:
        return 'Device';
    }
  }
}

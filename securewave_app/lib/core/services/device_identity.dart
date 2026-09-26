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
  final String type;

  static Future<DeviceIdentity> load() async {
    final storage = SecureStorage();

    var installId = await storage.getString(SecureStorage.deviceInstallIdKey);
    if (installId == null || installId.trim().isEmpty) {
      installId = const Uuid().v4();
      await storage.saveString(SecureStorage.deviceInstallIdKey, installId);
    }

    const type = 'linux';
    var name = await storage.getString(SecureStorage.deviceNameKey);
    if (name == null || name.trim().isEmpty) {
      final suffix =
          installId.replaceAll('-', '').substring(0, 4).toUpperCase();
      name = 'Linux device ($suffix)';
      await storage.saveString(SecureStorage.deviceNameKey, name);
    }

    return DeviceIdentity(installId: installId, name: name, type: type);
  }
}

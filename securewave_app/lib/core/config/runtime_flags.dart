import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const bool _uiAutomationEnabled =
    bool.fromEnvironment('SECUREWAVE_UI_AUTOMATION', defaultValue: false);

final uiAutomationEnabledProvider = Provider<bool>((ref) {
  return _uiAutomationEnabled;
});

final deferPostAuthAutoConnectProvider = Provider<bool>((ref) {
  final automationEnabled = ref.watch(uiAutomationEnabledProvider);
  return automationEnabled &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.linux;
});

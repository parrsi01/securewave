import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_ui_v1.dart';

/// Centralized haptics so we can keep UX consistent and gate by platform.
class AppHaptics {
  const AppHaptics._();

  static Future<void> connectTap() async {
    if (!_enabled) return;
    await HapticFeedback.mediumImpact();
  }

  static Future<void> disconnectTap() async {
    if (!_enabled) return;
    await HapticFeedback.lightImpact();
  }

  static Future<void> connectConfirmed() async {
    if (!_enabled) return;
    await HapticFeedback.lightImpact();
  }

  static Future<void> disconnectConfirmed() async {
    if (!_enabled) return;
    await HapticFeedback.selectionClick();
  }

  static Future<void> panicTap() async {
    if (!_enabled) return;
    await HapticFeedback.heavyImpact();
  }

  static bool get _enabled => !kIsWeb && AppUIv1.isApplePlatform;
}

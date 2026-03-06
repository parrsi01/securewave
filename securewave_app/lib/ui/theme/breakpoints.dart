import 'package:flutter/widgets.dart';

enum SecureWaveBreakpoint { mobile, tablet, desktop }

class SecureWaveBreakpoints {
  const SecureWaveBreakpoints._();

  static SecureWaveBreakpoint of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) {
      return SecureWaveBreakpoint.mobile;
    }
    if (width <= 1000) {
      return SecureWaveBreakpoint.tablet;
    }
    return SecureWaveBreakpoint.desktop;
  }

  static bool isMobile(BuildContext context) =>
      of(context) == SecureWaveBreakpoint.mobile;

  static bool isTablet(BuildContext context) =>
      of(context) == SecureWaveBreakpoint.tablet;

  static bool isDesktop(BuildContext context) =>
      of(context) == SecureWaveBreakpoint.desktop;
}

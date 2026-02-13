/// SecureWave spacing scale (8dp grid system).
///
/// Provides consistent spacing throughout the app.
/// Based on 4dp increments, aligned to 8dp grid.
class AppSpacing {
  AppSpacing._();

  /// 4dp - Smallest spacing unit
  static const double space1 = 4;

  /// 8dp - Base grid unit
  static const double space2 = 8;

  /// 12dp - Small spacing
  static const double space3 = 12;

  /// 16dp - Medium spacing (most common)
  static const double space4 = 16;

  /// 24dp - Large spacing
  static const double space5 = 24;

  /// 32dp - Extra large spacing
  static const double space6 = 32;

  /// 48dp - Section spacing
  static const double space7 = 48;

  /// 64dp - Page spacing
  static const double space8 = 64;

  // ── Border Radii ────────────────────────────────────────────────────────

  /// Small radius (8dp) - Buttons, small cards
  static const double radiusS = 8;

  /// Medium radius (12dp) - Input fields, dialogs
  static const double radiusM = 12;

  /// Large radius (16dp) - Large cards, sheets
  static const double radiusL = 16;

  /// Extra large radius (20dp) - Hero elements
  static const double radiusXL = 20;

  /// Full radius (999dp) - Fully rounded (pills, chips)
  static const double radiusFull = 999;

  // ── Layout Constraints ──────────────────────────────────────────────────

  /// Mobile breakpoint (600dp) - Below this = mobile layout
  static const double mobileBreakpoint = 600;

  /// Tablet breakpoint (900dp) - Below this = tablet, above = desktop
  static const double tabletBreakpoint = 900;

  /// Max width for auth screens (440dp)
  static const double authMaxWidth = 440;

  /// Max width for content sections (720dp)
  static const double contentMaxWidth = 720;
}

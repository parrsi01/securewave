/// SecureWave spacing scale — 8dp grid system.
///
/// Numeric scale, semantic aliases, icon sizes, and layout constants.
class AppSpacing {
  AppSpacing._();

  // ── Numeric Scale ────────────────────────────────────────────────────────

  /// 4dp - Micro spacing
  static const double space1 = 4;

  /// 8dp - Base grid unit
  static const double space2 = 8;

  /// 12dp - Small spacing
  static const double space3 = 12;

  /// 16dp - Medium spacing (most common)
  static const double space4 = 16;

  /// 24dp - Large spacing
  static const double space5 = 24;

  /// 32dp - Extra large
  static const double space6 = 32;

  /// 48dp - Section gap
  static const double space7 = 48;

  /// 64dp - Page spacing
  static const double space8 = 64;

  /// 96dp - Hero spacing
  static const double space9 = 96;

  // ── Semantic Aliases ─────────────────────────────────────────────────────

  static const double pagePadding = space4; // 16 — screen edges
  static const double cardPadding = space5; // 24 — inside cards
  static const double sectionGap = space5; // 24 — between sections
  static const double itemGap = space3; // 12 — between list items

  // ── Border Radii ─────────────────────────────────────────────────────────

  static const double radiusXS = 4;
  static const double radiusS = 8;
  static const double radiusM = 12;
  static const double radiusL = 16;
  static const double radiusXL = 20;
  static const double radiusXXL = 28;

  /// Fully rounded — pills, chips
  static const double radiusFull = 999;

  // ── Icon Sizes ─────────────────────────────────────────────────────────

  static const double iconXS = 14;
  static const double iconS = 18;
  static const double iconM = 22;
  static const double iconL = 28;
  static const double iconXL = 36;

  // ── Layout Breakpoints ─────────────────────────────────────────────────

  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 900;

  // ── Content Constraints ────────────────────────────────────────────────

  static const double authMaxWidth = 440;
  static const double contentMaxWidth = 720;
  static const double sidebarWidth = 240;
  static const double railWidth = 80;

  // ── Connection Ring ────────────────────────────────────────────────────

  static const double connectionRingSize = 220;
  static const double connectionRingStroke = 5;
}

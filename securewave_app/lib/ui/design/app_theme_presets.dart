import 'package:flutter/material.dart';

/// Adaptive theme preset system for SecureWave.
///
/// Each preset encodes professional-grade color semantics for a specific
/// application category. The VPN preset is the default — designed around
/// the #08CB00 / #253900 / #000000 / #EEEEEE palette from ColorHunt,
/// which reads as "secure ops / terminal / cyber-professional".
///
/// Usage:
///   AppTheme.forPreset(AppThemePreset.vpn)
///
/// Extending: add a new AppThemePreset value, then add a corresponding
/// AppPalette.forPreset() branch. Everything else auto-adapts.

// ── Preset enum ──────────────────────────────────────────────────────────────

enum AppThemePreset {
  /// VPN / Security / Privacy apps.
  /// Palette: cyber-green accent on pure-black ground, off-white text.
  /// Mood: secure ops, terminal, high-trust.
  vpn,

  /// Finance / Banking / Trading apps.
  /// Palette: gold accent, dark navy ground, clean white text.
  /// Mood: authoritative, premium, precise.
  finance,

  /// Health / Fitness / Wellness apps.
  /// Palette: teal accent, dark slate ground, warm white text.
  /// Mood: calm, trustworthy, clinical-clean.
  health,

  /// General purpose.
  /// Palette: indigo accent, neutral near-black, soft white text.
  /// Mood: modern, neutral, product-grade.
  general,
}

// ── Palette data class ───────────────────────────────────────────────────────

/// All raw color tokens for one theme preset.
/// Consumed by AppColors and AppTheme — never referenced directly in widgets.
class AppPalette {
  const AppPalette({
    // Accent
    required this.accent,
    required this.accentDim,
    required this.accentGhost,
    required this.onAccent, // text/icon color ON the accent fill
    // Secondary accent
    required this.secondary,
    required this.onSecondary,
    // Backgrounds (always dark)
    required this.background,
    required this.backgroundWarm,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceElevated,
    // Text
    required this.ink,
    required this.inkMuted,
    required this.inkSoft,
    // Borders
    required this.border,
    required this.borderFocus,
    // Semantic
    required this.success,
    required this.warning,
    required this.error,
    required this.successSurface,
    required this.warningSurface,
    required this.errorSurface,
    // Gradients
    required this.heroGradient,
    required this.brandGradient,
    required this.headerGradient,
    // Preset metadata
    required this.preset,
    required this.label,
  });

  final Color accent;
  final Color accentDim;
  final Color accentGhost;
  final Color onAccent;
  final Color secondary;
  final Color onSecondary;
  final Color background;
  final Color backgroundWarm;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceElevated;
  final Color ink;
  final Color inkMuted;
  final Color inkSoft;
  final Color border;
  final Color borderFocus;
  final Color success;
  final Color warning;
  final Color error;
  final Color successSurface;
  final Color warningSurface;
  final Color errorSurface;
  final Gradient heroGradient;
  final Gradient brandGradient;
  final Gradient headerGradient;
  final AppThemePreset preset;
  final String label;

  // ── Factory ───────────────────────────────────────────────────────────────

  factory AppPalette.forPreset(AppThemePreset preset) {
    return switch (preset) {
      AppThemePreset.vpn => _vpn,
      AppThemePreset.finance => _finance,
      AppThemePreset.health => _health,
      AppThemePreset.general => _general,
    };
  }

  // ── VPN preset ────────────────────────────────────────────────────────────
  // Source palette: #08CB00 | #253900 | #000000 | #EEEEEE
  // Design language: terminal-green, secure-ops, zero-noise.
  // - Background: pure black (#000000) — maximum contrast, no softening
  // - Surface: black tinted with #253900 at low opacity → almost-black green
  // - Accent: #08CB00 — only on connected/active state, CTAs, focus rings
  // - Text: #EEEEEE primary, desaturated greens for secondary/muted
  // - Borders: very subtle dark-green, nearly invisible
  // - Secondary: cyan-teal (#00C8B0) — for info pills, protocol labels

  static const AppPalette _vpn = AppPalette(
    preset: AppThemePreset.vpn,
    label: 'VPN Dark',

    // Accent — cyber-green, used ONLY for active/connected/CTA
    accent: Color(0xFF08CB00),
    accentDim: Color(0xFF069E00),
    accentGhost: Color(0x1408CB00),
    onAccent: Color(0xFF000000), // black text on bright green

    // Secondary — muted cyan for info/protocol context
    secondary: Color(0xFF00BFA5),
    onSecondary: Color(0xFF000000),

    // Surfaces — pure black base, dark-green tinted layers
    background: Color(0xFF000000), // pure black
    backgroundWarm: Color(0xFF050A05), // black with barely perceptible green
    surface: Color(0xFF0A140A), // dark forest surface (#253900 × 0.25)
    surfaceMuted: Color(0xFF111D11), // card fills
    surfaceElevated: Color(0xFF1A2E1A), // elevated modals/tooltips

    // Text — #EEEEEE primary, green-grey secondary/tertiary
    ink: Color(0xFFEEEEEE), // #EEEEEE from palette
    inkMuted: Color(0xFF8CAF8C), // desaturated mid-green
    inkSoft: Color(0xFF3D5C3D), // dim green for placeholders, labels

    // Borders — barely-visible green separators
    border: Color(0xFF1C3020), // #253900 at ~40% lightness
    borderFocus: Color(0xFF08CB00), // full accent on focus

    // Semantic — intentionally distinct from accent green
    success: Color(
        0xFF08CB00), // VPN connected = green (same as accent — intentional)
    warning: Color(0xFFFFAA00), // amber
    error: Color(0xFFFF3B30), // red
    successSurface: Color(0xFF081A08),
    warningSurface: Color(0xFF1A1200),
    errorSurface: Color(0xFF1A0808),

    // Gradients
    heroGradient: RadialGradient(
      center: Alignment.topCenter,
      radius: 1.6,
      colors: [Color(0xFF0A1F0A), Color(0xFF000000)],
      stops: [0.0, 1.0],
    ),
    brandGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF08CB00), Color(0xFF056B00)],
    ),
    headerGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0A2010), Color(0xFF000000)],
    ),
  );

  // ── Finance preset ────────────────────────────────────────────────────────
  // Gold accent (#D4AF37), dark navy base, clean near-white text.
  // Evokes Bloomberg Terminal, Robinhood dark, authoritative financial UI.

  static const AppPalette _finance = AppPalette(
    preset: AppThemePreset.finance,
    label: 'Finance Dark',

    accent: Color(0xFFD4AF37), // gold
    accentDim: Color(0xFFA88B2A),
    accentGhost: Color(0x1AD4AF37),
    onAccent: Color(0xFF0A0C14),

    secondary: Color(0xFF4D9EFF), // steel blue
    onSecondary: Color(0xFF0A0C14),

    background: Color(0xFF08090F),
    backgroundWarm: Color(0xFF0C0D14),
    surface: Color(0xFF111320),
    surfaceMuted: Color(0xFF191C2E),
    surfaceElevated: Color(0xFF222540),

    ink: Color(0xFFF0F2FA),
    inkMuted: Color(0xFF7A85A8),
    inkSoft: Color(0xFF3A4060),

    border: Color(0xFF1E2238),
    borderFocus: Color(0xFFD4AF37),

    success: Color(0xFF00C853),
    warning: Color(0xFFFFAA00),
    error: Color(0xFFFF3B30),
    successSurface: Color(0xFF051A08),
    warningSurface: Color(0xFF1A1200),
    errorSurface: Color(0xFF1A0808),

    heroGradient: RadialGradient(
      center: Alignment.topCenter,
      radius: 1.6,
      colors: [Color(0xFF15142A), Color(0xFF08090F)],
      stops: [0.0, 1.0],
    ),
    brandGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFD4AF37), Color(0xFF7A6420)],
    ),
    headerGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1A1830), Color(0xFF08090F)],
    ),
  );

  // ── Health preset ─────────────────────────────────────────────────────────
  // Calm teal (#00B8A4), dark blue-slate base.
  // Evokes Calm, Headspace, clinical app design. Trustworthy, clean.

  static const AppPalette _health = AppPalette(
    preset: AppThemePreset.health,
    label: 'Health Dark',

    accent: Color(0xFF00B8A4), // teal
    accentDim: Color(0xFF008C7C),
    accentGhost: Color(0x1A00B8A4),
    onAccent: Color(0xFF000E0D),

    secondary: Color(0xFF7B61FF), // soft purple
    onSecondary: Color(0xFF000E0D),

    background: Color(0xFF060C0B),
    backgroundWarm: Color(0xFF0A1210),
    surface: Color(0xFF0F1A18),
    surfaceMuted: Color(0xFF162420),
    surfaceElevated: Color(0xFF1E3530),

    ink: Color(0xFFE8F5F3),
    inkMuted: Color(0xFF6A9A94),
    inkSoft: Color(0xFF2E5550),

    border: Color(0xFF1A2F2C),
    borderFocus: Color(0xFF00B8A4),

    success: Color(0xFF00B8A4),
    warning: Color(0xFFFFAA00),
    error: Color(0xFFFF5A5A),
    successSurface: Color(0xFF061514),
    warningSurface: Color(0xFF1A1200),
    errorSurface: Color(0xFF1A0808),

    heroGradient: RadialGradient(
      center: Alignment.topCenter,
      radius: 1.6,
      colors: [Color(0xFF0A2220), Color(0xFF060C0B)],
      stops: [0.0, 1.0],
    ),
    brandGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF00B8A4), Color(0xFF006B60)],
    ),
    headerGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0A2A28), Color(0xFF060C0B)],
    ),
  );

  // ── General preset ────────────────────────────────────────────────────────
  // Indigo accent (#6C63FF), neutral near-black.
  // Clean, modern, product-grade. Works for any dark-first app.

  static const AppPalette _general = AppPalette(
    preset: AppThemePreset.general,
    label: 'General Dark',

    accent: Color(0xFF6C63FF), // indigo
    accentDim: Color(0xFF4A42CC),
    accentGhost: Color(0x1A6C63FF),
    onAccent: Color(0xFFFFFFFF),

    secondary: Color(0xFF00C8B0), // mint
    onSecondary: Color(0xFF000E0D),

    background: Color(0xFF08080F),
    backgroundWarm: Color(0xFF0C0C14),
    surface: Color(0xFF111120),
    surfaceMuted: Color(0xFF18192E),
    surfaceElevated: Color(0xFF222440),

    ink: Color(0xFFF0EFFF),
    inkMuted: Color(0xFF7A78A8),
    inkSoft: Color(0xFF3A3860),

    border: Color(0xFF1C1C38),
    borderFocus: Color(0xFF6C63FF),

    success: Color(0xFF00C853),
    warning: Color(0xFFFFAA00),
    error: Color(0xFFFF3B30),
    successSurface: Color(0xFF051A08),
    warningSurface: Color(0xFF1A1200),
    errorSurface: Color(0xFF1A0808),

    heroGradient: RadialGradient(
      center: Alignment.topCenter,
      radius: 1.6,
      colors: [Color(0xFF14142A), Color(0xFF08080F)],
      stops: [0.0, 1.0],
    ),
    brandGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF6C63FF), Color(0xFF3A30CC)],
    ),
    headerGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF181830), Color(0xFF08080F)],
    ),
  );
}

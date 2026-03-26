import 'package:flutter/material.dart';

import '../../debug/automation_keys.dart';
import '../design/app_spacing.dart';
import '../theme/app_colors.dart' as htb;
import '../theme/app_tokens.dart';
import '../widgets/brand_mark.dart';

/// Adaptive navigation shell.
///
/// Mobile  (< 600dp): NavigationBar at the bottom.
/// Tablet  (600-900dp): Compact icon-only NavigationRail on the left.
/// Desktop (>= 900dp):  Wide NavigationRail with labels on the left.
class AdaptiveShellScaffold extends StatelessWidget {
  const AdaptiveShellScaffold({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  static const _labels = ['Home', 'Servers', 'Connect', 'Settings', 'Account'];

  static const _icons = [
    Icons.home_outlined,
    Icons.public_outlined,
    Icons.shield_outlined,
    Icons.settings_outlined,
    Icons.person_outline_rounded,
  ];

  static const _activeIcons = [
    Icons.home_rounded,
    Icons.public_rounded,
    Icons.shield_rounded,
    Icons.settings_rounded,
    Icons.person_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width >= AppSpacing.mobileBreakpoint) {
      final wide = width >= AppSpacing.tabletBreakpoint;
      return Scaffold(
        key: AutomationKeys.shellRootScaffoldKey,
        body: Row(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space3,
                AppSpacing.space3,
                0,
                AppSpacing.space3,
              ),
              child: _DesktopRail(
                currentIndex: currentIndex,
                onDestinationSelected: onDestinationSelected,
                labels: _labels,
                icons: _icons,
                activeIcons: _activeIcons,
                showLabels: wide,
              ),
            ),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      key: AutomationKeys.shellRootScaffoldKey,
      body: child,
      bottomNavigationBar: _BottomBar(
        currentIndex: currentIndex,
        onDestinationSelected: onDestinationSelected,
        labels: _labels,
        icons: _icons,
        activeIcons: _activeIcons,
      ),
    );
  }
}

// ── Desktop rail ─────────────────────────────────────────────────────────────

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.labels,
    required this.icons,
    required this.activeIcons,
    required this.showLabels,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<String> labels;
  final List<IconData> icons;
  final List<IconData> activeIcons;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final w = showLabels ? AppSpacing.sidebarWidth : AppSpacing.railWidth;
    final bgColor = isDark ? htb.HtbColors.bg1 : cs.surface;

    return Container(
      width: w,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXXL),
        border: Border.all(
          color: isDark ? htb.HtbColors.divider : cs.outlineVariant,
          width: 1,
        ),
        boxShadow: isDark
            ? const [
                BoxShadow(
                  color: htb.HtbColors.accentSecondaryGhost,
                  blurRadius: 26,
                  offset: Offset(0, 18),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.space5),
          Padding(
            padding: EdgeInsets.fromLTRB(
              showLabels ? AppSpacing.space4 : 0,
              0,
              showLabels ? AppSpacing.space4 : 0,
              0,
            ),
            child: showLabels
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.space3),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          htb.HtbColors.accentSecondaryGhost,
                          htb.HtbColors.accentPrimaryGhost,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
                      border: Border.all(
                        color: htb.HtbColors.glassBorderDefault,
                      ),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BrandMark(size: 20, textSize: 14),
                        SizedBox(height: AppSpacing.space2),
                        Text(
                          'CONTROL MESH',
                          style: TextStyle(
                            color: htb.HtbColors.textMono,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  )
                : const Center(child: BrandMark(size: 28, showText: false)),
          ),
          const SizedBox(height: AppSpacing.space5),
          for (var i = 0; i < labels.length; i++)
            _RailItem(
              icon: icons[i],
              activeIcon: activeIcons[i],
              label: labels[i],
              selected: currentIndex == i,
              onTap: () => onDestinationSelected(i),
              showLabel: showLabels,
            ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.showLabel,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final activeColor = isDark ? htb.HtbColors.accentPrimary : cs.primary;
    final inactiveColor =
        isDark ? htb.HtbColors.textSecondary : cs.onSurfaceVariant;
    final activeBg = isDark
        ? htb.HtbColors.accentPrimaryGhost
        : cs.primary.withValues(alpha: 0.1);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space2,
        vertical: AppSpacing.space1,
      ),
      child: AnimatedContainer(
        duration: AppTokens.durationNormal,
        curve: AppTokens.curveDefault,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    activeBg,
                    htb.HtbColors.accentSecondaryGhost.withValues(alpha: 0.22),
                  ],
                )
              : null,
          boxShadow: selected && isDark
              ? const [
                  BoxShadow(
                    color: htb.HtbColors.accentSecondaryGhost,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusL),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: AutomationKeys.navDestinationKey(label),
            onTap: onTap,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: showLabel ? AppSpacing.space3 : 0,
                  vertical: AppSpacing.space3,
                ),
                child: showLabel
                    ? Row(
                        children: [
                          AnimatedContainer(
                            duration: AppTokens.durationNormal,
                            curve: AppTokens.curveDefault,
                            width: 4,
                            height: selected ? 30 : 14,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              gradient: selected
                                  ? const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        htb.HtbColors.accentSecondary,
                                        htb.HtbColors.accentPrimary,
                                      ],
                                    )
                                  : null,
                              color: selected ? null : Colors.transparent,
                              borderRadius: AppTokens.brSmall,
                              boxShadow: selected && isDark
                                  ? const <BoxShadow>[
                                      BoxShadow(
                                        color: htb.HtbColors.glowSecondary,
                                        blurRadius: 10,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                          Icon(
                            selected ? activeIcon : icon,
                            color: selected ? activeColor : inactiveColor,
                            size: 20,
                          ),
                          const SizedBox(width: AppSpacing.space3),
                          Expanded(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected ? activeColor : inactiveColor,
                                letterSpacing: selected ? 0.3 : 0,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: AppTokens.durationNormal,
                            curve: AppTokens.curveDefault,
                            padding: const EdgeInsets.all(AppSpacing.space2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: selected
                                  ? const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: <Color>[
                                        htb.HtbColors.accentSecondaryGhost,
                                        htb.HtbColors.accentPrimaryGhost,
                                      ],
                                    )
                                  : null,
                            ),
                            child: Icon(
                              selected ? activeIcon : icon,
                              color: selected ? activeColor : inactiveColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected ? activeColor : inactiveColor,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mobile bottom bar ─────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.labels,
    required this.icons,
    required this.activeIcons,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<String> labels;
  final List<IconData> icons;
  final List<IconData> activeIcons;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space3,
        0,
        AppSpacing.space3,
        AppSpacing.space3,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? htb.HtbColors.bg1 : cs.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXXL),
          border: Border.all(
            color: isDark ? htb.HtbColors.divider : cs.outlineVariant,
            width: 1,
          ),
          boxShadow: isDark
              ? const [
                  BoxShadow(
                    color: htb.HtbColors.accentSecondaryGhost,
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ]
              : null,
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: _BarItem(
                    icon: icons[i],
                    activeIcon: activeIcons[i],
                    label: labels[i],
                    selected: currentIndex == i,
                    onTap: () => onDestinationSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final activeColor = isDark ? htb.HtbColors.accentPrimary : cs.primary;
    final inactiveColor =
        isDark ? htb.HtbColors.textSecondary : cs.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: AutomationKeys.navDestinationKey(label),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space1,
            vertical: AppSpacing.space2,
          ),
          child: AnimatedContainer(
            duration: AppTokens.durationNormal,
            curve: AppTokens.curveDefault,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
              gradient: selected
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        htb.HtbColors.accentSecondaryGhost,
                        htb.HtbColors.accentPrimaryGhost,
                      ],
                    )
                  : null,
              boxShadow: selected && isDark
                  ? const [
                      BoxShadow(
                        color: htb.HtbColors.accentSecondaryGhost,
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? activeIcon : icon,
                  color: selected ? activeColor : inactiveColor,
                  size: 22,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? activeColor : inactiveColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

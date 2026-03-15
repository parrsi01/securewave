import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_spacing.dart';

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

  static const _labels = [
    'Home',
    'Servers',
    'Connect',
    'Settings',
    'Account',
  ];

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
        body: Row(
          children: [
            _DesktopRail(
              currentIndex: currentIndex,
              onDestinationSelected: onDestinationSelected,
              labels: _labels,
              icons: _icons,
              activeIcons: _activeIcons,
              showLabels: wide,
            ),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
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
    final bgColor = isDark ? AppColors.darkBackgroundWarm : cs.surface;

    return Container(
      width: w,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          right: BorderSide(
            color: isDark ? AppColors.darkBorder : cs.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.space6),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: showLabels ? AppSpacing.space4 : 0,
            ),
            child: showLabels
                ? const Row(
                    children: [
                      SizedBox(width: AppSpacing.space2),
                      Icon(
                        Icons.shield_rounded,
                        color: AppColors.primaryBright,
                        size: 24,
                      ),
                      SizedBox(width: AppSpacing.space2),
                      Text(
                        'SecureWave',
                        style: TextStyle(
                          color: AppColors.primaryBright,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  )
                : const Center(
                    child: Icon(
                      Icons.shield_rounded,
                      color: AppColors.primaryBright,
                      size: 28,
                    ),
                  ),
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
    final cs = Theme.of(context).colorScheme;
    final activeColor = cs.primary;
    final inactiveColor = cs.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space2,
        vertical: AppSpacing.space1,
      ),
      child: Material(
        color: selected
            ? cs.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
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
                        Icon(
                          selected ? activeIcon : icon,
                          color: selected ? activeColor : inactiveColor,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpacing.space3),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: selected ? activeColor : inactiveColor,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selected ? activeIcon : icon,
                          color: selected ? activeColor : inactiveColor,
                          size: 22,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: selected ? activeColor : inactiveColor,
                          ),
                        ),
                      ],
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

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackgroundWarm : cs.surface,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : cs.outlineVariant,
            width: 1,
          ),
        ),
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
    final cs = Theme.of(context).colorScheme;
    final activeColor = cs.primary;
    final inactiveColor = cs.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
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
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

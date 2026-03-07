import 'package:flutter/material.dart';

import '../design/app_colors.dart';
import '../design/app_spacing.dart';

/// Adaptive navigation shell.
///
/// Mobile (< 600dp): NavigationBar at the bottom.
/// Desktop/tablet (≥ 600dp): NavigationRail on the left.
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
    final useRail = width >= AppSpacing.mobileBreakpoint;

    if (useRail) {
      return Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: Row(
          children: [
            _DesktopRail(
              currentIndex: currentIndex,
              onDestinationSelected: onDestinationSelected,
              labels: _labels,
              icons: _icons,
              activeIcons: _activeIcons,
            ),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
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
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<String> labels;
  final List<IconData> icons;
  final List<IconData> activeIcons;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.railWidth,
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        border: Border(
          right: BorderSide(color: AppColors.darkBorder, width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.space6),
          // Logo
          Icon(
            Icons.shield_rounded,
            color: AppColors.primaryBright,
            size: 28,
          ),
          const SizedBox(height: AppSpacing.space5),
          for (var i = 0; i < labels.length; i++)
            _RailItem(
              icon: icons[i],
              activeIcon: activeIcons[i],
              label: labels[i],
              selected: currentIndex == i,
              onTap: () => onDestinationSelected(i),
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
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space2,
        vertical: AppSpacing.space1,
      ),
      child: Material(
        color: selected
            ? AppColors.primaryBright.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusM),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? activeIcon : icon,
                    color: selected
                        ? AppColors.primaryBright
                        : AppColors.darkInkSoft,
                    size: 22,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected
                          ? AppColors.primaryBright
                          : AppColors.darkInkSoft,
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        border: Border(
          top: BorderSide(color: AppColors.darkBorder, width: 1),
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? activeIcon : icon,
              color: selected
                  ? AppColors.primaryBright
                  : AppColors.darkInkSoft,
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w400,
                color: selected
                    ? AppColors.primaryBright
                    : AppColors.darkInkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

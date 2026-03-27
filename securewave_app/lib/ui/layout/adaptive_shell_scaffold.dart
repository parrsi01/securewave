import 'package:flutter/material.dart';

import '../../debug/automation_keys.dart';
import '../design/app_animations.dart';
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
        boxShadow: const [
          BoxShadow(
            color: Color(0x30020306),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
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
                      color: htb.HtbColors.bg0,
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

class _RailItem extends StatefulWidget {
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
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hovered = false;
  bool _pressed = false;

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
    final isHighlighted = _hovered || _pressed;
    final currentColor = widget.selected
        ? activeColor
        : isHighlighted
            ? htb.HtbColors.textPrimary
            : inactiveColor;
    final scale = _pressed
        ? AppAnimations.buttonPressScale
        : _hovered
            ? AppAnimations.buttonHoverScale
            : 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space2,
        vertical: AppSpacing.space1,
      ),
      child: AnimatedScale(
        scale: scale,
        duration: _pressed
            ? AppAnimations.durationPress
            : AppAnimations.durationHover,
        curve: AppAnimations.curveDefault,
        child: AnimatedContainer(
          duration: AppAnimations.durationHover,
          curve: AppAnimations.curveDefault,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusL),
            color: widget.selected
                ? activeBg
                : isHighlighted
                    ? htb.HtbColors.bg2
                    : Colors.transparent,
            border: Border.all(
              color: widget.selected
                  ? htb.HtbColors.accentPrimary.withValues(alpha: 0.18)
                  : isHighlighted
                      ? htb.HtbColors.border
                      : Colors.transparent,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusL),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: AutomationKeys.navDestinationKey(widget.label),
              onTap: widget.onTap,
              onHover: (value) {
                if (_hovered == value) return;
                setState(() => _hovered = value);
              },
              onHighlightChanged: (value) {
                if (_pressed == value) return;
                setState(() => _pressed = value);
              },
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return htb.HtbColors.accentPrimaryGhost;
                }
                if (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)) {
                  return htb.HtbColors.accentPrimaryHover;
                }
                return Colors.transparent;
              }),
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.showLabel ? AppSpacing.space3 : 0,
                    vertical: AppSpacing.space3,
                  ),
                  child: widget.showLabel
                      ? Row(
                          children: [
                            AnimatedContainer(
                              duration: AppAnimations.durationHover,
                              curve: AppAnimations.curveDefault,
                              width: 4,
                              height: widget.selected ? 30 : 14,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                color: widget.selected
                                    ? htb.HtbColors.accentPrimary
                                    : isHighlighted
                                        ? htb.HtbColors.borderStrong
                                        : Colors.transparent,
                                borderRadius: AppTokens.brSmall,
                              ),
                            ),
                            Icon(
                              widget.selected ? widget.activeIcon : widget.icon,
                              color: currentColor,
                              size: 20,
                            ),
                            const SizedBox(width: AppSpacing.space3),
                            Expanded(
                              child: Text(
                                widget.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: widget.selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: currentColor,
                                  letterSpacing: widget.selected ? 0.3 : 0,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: AppAnimations.durationHover,
                              curve: AppAnimations.curveDefault,
                              padding: const EdgeInsets.all(AppSpacing.space2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.selected
                                    ? activeBg
                                    : isHighlighted
                                        ? htb.HtbColors.bg2
                                        : Colors.transparent,
                              ),
                              child: Icon(
                                widget.selected
                                    ? widget.activeIcon
                                    : widget.icon,
                                color: currentColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: widget.selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: currentColor,
                              ),
                            ),
                          ],
                        ),
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
          boxShadow: const [
            BoxShadow(
              color: Color(0x28020306),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
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

class _BarItem extends StatefulWidget {
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
  State<_BarItem> createState() => _BarItemState();
}

class _BarItemState extends State<_BarItem> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final activeColor = isDark ? htb.HtbColors.accentPrimary : cs.primary;
    final inactiveColor =
        isDark ? htb.HtbColors.textSecondary : cs.onSurfaceVariant;
    final isHighlighted = _hovered || _pressed;
    final currentColor = widget.selected
        ? activeColor
        : isHighlighted
            ? htb.HtbColors.textPrimary
            : inactiveColor;
    final scale = _pressed
        ? AppAnimations.buttonPressScale
        : _hovered
            ? AppAnimations.buttonHoverScale
            : 1.0;

    return AnimatedScale(
      scale: scale,
      duration:
          _pressed ? AppAnimations.durationPress : AppAnimations.durationHover,
      curve: AppAnimations.curveDefault,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: AutomationKeys.navDestinationKey(widget.label),
          onTap: widget.onTap,
          onHover: (value) {
            if (_hovered == value) return;
            setState(() => _hovered = value);
          },
          onHighlightChanged: (value) {
            if (_pressed == value) return;
            setState(() => _pressed = value);
          },
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return htb.HtbColors.accentPrimaryGhost;
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return htb.HtbColors.accentPrimaryHover;
            }
            return Colors.transparent;
          }),
          borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space1,
              vertical: AppSpacing.space2,
            ),
            child: AnimatedContainer(
              duration: AppAnimations.durationHover,
              curve: AppAnimations.curveDefault,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSpacing.radiusXL),
                color: widget.selected
                    ? htb.HtbColors.accentPrimaryGhost
                    : isHighlighted
                        ? htb.HtbColors.bg2
                        : Colors.transparent,
                border: Border.all(
                  color: widget.selected
                      ? htb.HtbColors.accentPrimary.withValues(alpha: 0.18)
                      : isHighlighted
                          ? htb.HtbColors.border
                          : Colors.transparent,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.selected ? widget.activeIcon : widget.icon,
                    color: currentColor,
                    size: 22,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          widget.selected ? FontWeight.w700 : FontWeight.w500,
                      color: currentColor,
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

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/vpn_state.dart';
import '../../debug/automation_keys.dart';
import '../../navigation/nav_destinations.dart';
import '../components/status_indicator.dart';
import '../theme/securewave_theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/vpn_ui_bindings.dart';
import 'layout_tokens.dart';

class AdaptiveShellScaffold extends ConsumerWidget {
  const AdaptiveShellScaffold({
    super.key,
    required this.child,
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  final Widget child;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnStateProvider);
    final visualState = resolveConnectionVisualState(
      vpn,
      ref.read(vpnStateProvider.notifier).recentTransitions,
    );
    final width = MediaQuery.sizeOf(context).width;
    final showRail = width >= LayoutTokens.tabletBreakpoint;
    final expandedRail = width >= SecureWaveBreakpoints.expanded;

    final shellChild = PageTransitionSwitcher(
      duration: const Duration(milliseconds: 280),
      transitionBuilder: (child, primaryAnimation, secondaryAnimation) {
        return SharedAxisTransition(
          animation: primaryAnimation,
          secondaryAnimation: secondaryAnimation,
          transitionType: SharedAxisTransitionType.horizontal,
          fillColor: Colors.transparent,
          child: child,
        );
      },
      child: KeyedSubtree(
        key: ValueKey<int>(currentIndex),
        child: child,
      ),
    );

    if (showRail) {
      return Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: context.swGradients.canvas),
          child: SafeArea(
            child: Row(
              children: <Widget>[
                Container(
                  width: expandedRail
                      ? LayoutTokens.expandedRailWidth
                      : LayoutTokens.railWidth,
                  margin: const EdgeInsets.fromLTRB(16, 16, 0, 16),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: context.swGradients.panel,
                    borderRadius:
                        BorderRadius.circular(LayoutTokens.shellRadius),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outline
                          .withValues(alpha: 0.28),
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: expandedRail ? 18 : 0,
                        ),
                        child: expandedRail
                            ? const BrandMark()
                            : const BrandMark(showWordmark: false),
                      ),
                      const SizedBox(height: 18),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: expandedRail ? 12 : 8,
                        ),
                        child: StatusIndicator(
                          label: vpn.statusText(),
                          color: StatusIndicator.colorFor(visualState),
                          icon: StatusIndicator.iconFor(visualState),
                          emphasized: expandedRail,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: NavigationRail(
                          selectedIndex: currentIndex,
                          onDestinationSelected: onDestinationSelected,
                          extended: expandedRail,
                          leading: const SizedBox.shrink(),
                          backgroundColor: Colors.transparent,
                          labelType: expandedRail
                              ? NavigationRailLabelType.none
                              : NavigationRailLabelType.all,
                          destinations: NavDestinations.all
                              .map(
                                (destination) => NavigationRailDestination(
                                  icon: Icon(
                                    destination.icon,
                                    key: ValueKey<String>(
                                      AutomationKeys.navDestination(
                                        destination.label,
                                      ),
                                    ),
                                  ),
                                  selectedIcon: Icon(destination.selectedIcon),
                                  label: Text(destination.label),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: shellChild),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const BrandMark(size: 34),
        titleSpacing: 16,
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: StatusIndicator(
                label: vpn.statusText(),
                color: StatusIndicator.colorFor(visualState),
                icon: StatusIndicator.iconFor(visualState),
              ),
            ),
          ),
        ],
      ),
      body: shellChild,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: NavDestinations.all
            .map(
              (destination) => NavigationDestination(
                icon: Icon(
                  destination.icon,
                  key: ValueKey<String>(
                    AutomationKeys.navDestination(destination.label),
                  ),
                ),
                selectedIcon: Icon(destination.selectedIcon),
                label: destination.label,
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

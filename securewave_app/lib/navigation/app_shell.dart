import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../debug/automation_keys.dart';
import '../ui/layout/adaptive_shell_scaffold.dart';
import '../ui/widgets/vpn_ui_bindings.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visualState = ref.watch(connectionVisualStateProvider);

    return AdaptiveShellScaffold(
      currentIndex: navigationShell.currentIndex,
      onDestinationSelected: (index) {
        navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        );
      },
      child: Stack(
        children: [
          navigationShell,
          IgnorePointer(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                key: AutomationKeys.shellConnectionStateKey(
                  visualState.name,
                ),
                width: 0,
                height: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'dashboard_container.dart';

class AdaptiveShellScaffold extends StatelessWidget {
  const AdaptiveShellScaffold({
    super.key,
    required this.child,
    this.floatingActionButton,
  });

  final Widget child;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: SecureWaveTokens.backgroundGradient,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: floatingActionButton,
        body: SafeArea(
          child: DashboardContainer(child: child),
        ),
      ),
    );
  }
}

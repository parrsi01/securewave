import 'package:flutter/material.dart';

import '../services/account_usage.dart';
import 'monthly_usage.dart';
import 'theme.dart';

/// Read-only account and VPN summaries; scrolling is a small-window fallback.
class SettingsView extends StatelessWidget {
  const SettingsView(
      {super.key,
      required this.store,
      required this.location,
      required this.connectionStatus,
      required this.onBack,
      required this.onRefresh});
  final AccountUsageStore store;
  final String location, connectionStatus;
  final VoidCallback onBack, onRefresh;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.backgroundPrimary,
          title: const Text('Settings'),
          leading: MergeSemantics(
              child: Semantics(
                  label: 'Back to VPN',
                  button: true,
                  child: IconButton(
                      tooltip: 'Back to VPN',
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back)))),
        ),
        body: SafeArea(child: LayoutBuilder(builder: (context, viewport) {
          final padding = AppTheme.outerPadding(viewport.maxWidth);
          final wide = viewport.maxWidth >= 760 &&
              MediaQuery.textScalerOf(context).scale(16) / 16 < 1.5;
          final account = _section('Account', [
            _row(context, 'Email', store.summary?.email ?? 'Loading account…'),
            _row(context, 'Account type',
                store.summary?.planName ?? 'Unavailable'),
          ]);
          final vpn = _section('VPN', [
            _row(context, 'Location', location),
            _row(context, 'Connection', connectionStatus),
            _row(context, 'Protocol', 'WireGuard'),
            _row(context, 'App version', '1.0.0'),
          ]);
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: padding, vertical: 16),
            child: Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wide)
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: account),
                            const SizedBox(width: 32),
                            Expanded(child: vpn),
                          ])
                    else ...[account, const SizedBox(height: 16), vpn],
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),
                    MonthlyUsageView(
                        store: store, onRefresh: onRefresh, compact: true),
                    const SizedBox(height: 16),
                    Text(
                        'Upload and download count toward your allowance. Usage stays saved after disconnecting or signing out.',
                        style: AppTheme.smallBody),
                  ]),
            )),
          );
        })),
      );

  Widget _section(String title, List<Widget> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTheme.sectionTitle),
          const SizedBox(height: 12),
          ...rows
        ],
      );

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: LayoutBuilder(builder: (context, constraints) {
          final stacked = constraints.maxWidth < 280 ||
              MediaQuery.textScalerOf(context).scale(16) / 16 >= 1.5;
          final name = Text(label,
              style:
                  AppTheme.smallBody.copyWith(color: AppTheme.textSecondary));
          final content = SelectableText(value, style: AppTheme.body);
          return stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [name, const SizedBox(height: 4), content])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 104, child: name),
                  const SizedBox(width: 12),
                  Expanded(child: content),
                ]);
        }),
      );
}

import 'package:flutter/material.dart';

import '../services/account_usage.dart';
import 'monthly_usage.dart';
import 'theme.dart';

/// A summary, with no settings that pretend to control unavailable features.
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
          leading: IconButton(
              tooltip: 'Back to VPN',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back)),
        ),
        body: SafeArea(
            child: SingleChildScrollView(
          padding: EdgeInsets.all(
              AppTheme.outerPadding(MediaQuery.sizeOf(context).width)),
          child: Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Account', style: AppTheme.sectionTitle),
                  const SizedBox(height: 16),
                  _row('Email', store.summary?.email ?? 'Loading account…'),
                  _row(
                      'Account type', store.summary?.planName ?? 'Unavailable'),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 16),
                  MonthlyUsageView(store: store, onRefresh: onRefresh),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),
                  Text('VPN', style: AppTheme.sectionTitle),
                  const SizedBox(height: 16),
                  _row('Location', location),
                  _row('Connection', connectionStatus),
                  _row('Protocol', 'WireGuard'),
                  _row('App version', '1.0.0'),
                  const SizedBox(height: 16),
                  Text(
                      'Upload and download both count toward your allowance. Saved usage remains after disconnecting or signing out.',
                      style: AppTheme.smallBody),
                ]),
          )),
        )),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: AppTheme.caption),
          const SizedBox(height: 4),
          SelectableText(value, style: AppTheme.body),
        ]),
      );
}

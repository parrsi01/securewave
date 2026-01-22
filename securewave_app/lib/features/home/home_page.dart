import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../widgets/buttons/primary_button.dart';
import '../../widgets/buttons/secondary_button.dart';
import '../../widgets/cards/metric_card.dart';
import '../../widgets/layouts/app_background.dart';
import '../../widgets/layouts/content_layout.dart';
import '../../widgets/layouts/section_header.dart';
import '../../widgets/layouts/responsive_wrap.dart';
import '../../core/theme/app_assets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: ContentLayout(
            child: ListView(
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E1B4B), Color(0xFF111827)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SvgPicture.asset(AppAssets.logo, height: 72),
                      const SizedBox(height: 12),
                      Text('SecureWave',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)),
                      const SizedBox(height: 8),
                      Text('Private VPN access with a streamlined control plane.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70)),
                      const SizedBox(height: 20),
                      PrimaryButton(
                        label: 'Sign in',
                        icon: Icons.lock,
                        onPressed: () => context.go('/login'),
                      ),
                      const SizedBox(height: 12),
                      SecondaryButton(
                        label: 'Create account',
                        icon: Icons.person_add,
                        onPressed: () => context.go('/register'),
                      ),
                      const SizedBox(height: 16),
                      ResponsiveWrap(
                        minItemWidth: 150,
                        children: const [
                          _QuickChip(label: 'Fast setup', icon: Icons.bolt),
                          _QuickChip(label: 'WireGuard', icon: Icons.shield),
                          _QuickChip(label: '5 GB free', icon: Icons.data_usage),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const SectionHeader(
                  title: 'How SecureWave works',
                  subtitle: 'Manage access here. Connect in the app.',
                ),
                const SizedBox(height: 16),
                ResponsiveWrap(
                  minItemWidth: 200,
                  children: const [
                    MetricCard(label: 'Step 1', value: 'Create account', icon: Icons.person_add),
                    MetricCard(label: 'Step 2', value: 'Provision device', icon: Icons.devices),
                    MetricCard(label: 'Step 3', value: 'Connect in SecureWave', icon: Icons.shield),
                  ],
                ),
                const SizedBox(height: 24),
                const SectionHeader(
                  title: 'Why SecureWave',
                  subtitle: 'Fast, private, and built for daily use.',
                ),
                const SizedBox(height: 16),
                ResponsiveWrap(
                  minItemWidth: 240,
                  children: const [
                    _FeatureTile(
                      icon: Icons.speed,
                      title: 'Fast by design',
                      subtitle: 'Low-latency routing and modern encryption.',
                    ),
                    _FeatureTile(
                      icon: Icons.lock,
                      title: 'Private by default',
                      subtitle: 'Your traffic stays encrypted end-to-end.',
                    ),
                    _FeatureTile(
                      icon: Icons.devices_other,
                      title: 'Device-ready',
                      subtitle: 'Provision devices and manage access from one place.',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../widgets/buttons/primary_button.dart';
import '../../widgets/buttons/secondary_button.dart';
import '../../widgets/cards/metric_card.dart';
import '../../widgets/layouts/content_layout.dart';
import '../../widgets/layouts/section_header.dart';
import '../../core/theme/app_assets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
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
                    SvgPicture.asset(AppAssets.logo, height: 64),
                    const SizedBox(height: 12),
                    Text('SecureWave',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)),
                    const SizedBox(height: 8),
                    Text('Private, fast VPN access managed by a simple control plane.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70)),
                    const SizedBox(height: 20),
                    PrimaryButton(label: 'Sign in', onPressed: () => context.go('/login')),
                    const SizedBox(height: 12),
                    SecondaryButton(label: 'Create account', onPressed: () => context.go('/register')),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const SectionHeader(
                title: 'How SecureWave works',
                subtitle: 'Manage access here, connect in the SecureWave app.',
              ),
              const SizedBox(height: 16),
              const MetricCard(label: 'Step 1', value: 'Create account', icon: Icons.person_add),
              const SizedBox(height: 12),
              const MetricCard(label: 'Step 2', value: 'Provision device', icon: Icons.devices),
              const SizedBox(height: 12),
              const MetricCard(label: 'Step 3', value: 'Connect in app', icon: Icons.shield),
              const SizedBox(height: 24),
              const SectionHeader(
                title: 'Why SecureWave',
                subtitle: 'WireGuard speed with a clean, reliable experience.',
              ),
              const SizedBox(height: 16),
              const _FeatureTile(
                icon: Icons.speed,
                title: 'Fast by design',
                subtitle: 'Low-latency routing and modern encryption.',
              ),
              const _FeatureTile(
                icon: Icons.lock,
                title: 'Private by default',
                subtitle: 'Your traffic stays encrypted end-to-end.',
              ),
              const _FeatureTile(
                icon: Icons.devices_other,
                title: 'Device-ready',
                subtitle: 'Provision devices and manage access from one place.',
              ),
            ],
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

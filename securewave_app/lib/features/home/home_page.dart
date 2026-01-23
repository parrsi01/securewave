import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/buttons/primary_button.dart';
import '../../widgets/buttons/secondary_button.dart';
import '../../widgets/cards/metric_card.dart';
import '../../widgets/layouts/app_background.dart';
import '../../widgets/layouts/brand_logo.dart';
import '../../widgets/layouts/content_layout.dart';
import '../../widgets/layouts/section_header.dart';
import '../../widgets/layouts/responsive_wrap.dart';

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
                // Hero Card
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0B1120), Color(0xFF0E7490), Color(0xFF14B8A6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                        blurRadius: 30,
                        offset: const Offset(0, 15),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BrandLogo(size: 52, showGlow: true),
                      const SizedBox(height: 16),
                      Text(
                        'SecureWave',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Fast, private access powered by the SecureWave app.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Colors.white.withValues(alpha: 0.8),
                              height: 1.5,
                            ),
                      ),
                      const SizedBox(height: 24),
                      PrimaryButton(
                        label: 'Sign in',
                        icon: Icons.login,
                        onPressed: () => context.go('/login'),
                      ),
                      const SizedBox(height: 12),
                      SecondaryButton(
                        label: 'Create free account',
                        icon: Icons.person_add_outlined,
                        onPressed: () => context.go('/register'),
                      ),
                      const SizedBox(height: 20),
                      ResponsiveWrap(
                        minItemWidth: 130,
                        spacing: 10,
                        runSpacing: 10,
                        children: const [
                          _QuickChip(label: 'Fast setup', icon: Icons.bolt),
                          _QuickChip(label: 'Auto-connect', icon: Icons.shield),
                          _QuickChip(label: '5 GB free', icon: Icons.data_usage),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                const SectionHeader(
                  title: 'How it works',
                  subtitle: 'Three simple steps to secure your connection.',
                ),
                const SizedBox(height: 20),
                ResponsiveWrap(
                  minItemWidth: 180,
                  children: const [
                    MetricCard(label: 'Step 1', value: 'Create account', icon: Icons.person_add, gradient: true),
                    MetricCard(label: 'Step 2', value: 'Download app', icon: Icons.download),
                    MetricCard(label: 'Step 3', value: 'Toggle VPN', icon: Icons.shield),
                  ],
                ),
                const SizedBox(height: 32),
                const SectionHeader(
                  title: 'Why SecureWave',
                  subtitle: 'Built for everyday privacy.',
                ),
                const SizedBox(height: 20),
                const _FeatureTile(
                  icon: Icons.speed,
                  title: 'Fast by design',
                  subtitle: 'Smart routing keeps your connection fast.',
                ),
                const _FeatureTile(
                  icon: Icons.lock_outline,
                  title: 'Private by default',
                  subtitle: 'Zero-log policy. Your data stays yours.',
                ),
                const _FeatureTile(
                  icon: Icons.devices_other,
                  title: 'Multi-device ready',
                  subtitle: 'Manage devices and access easily.',
                ),
                const SizedBox(height: 24),
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
    final color = Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

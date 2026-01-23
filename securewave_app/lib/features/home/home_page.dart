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
                // Hero Card - v4.0 Enhanced
                Container(
                  padding: const EdgeInsets.all(36),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0B1120), Color(0xFF0E7490), Color(0xFF14B8A6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.35),
                        blurRadius: 48,
                        offset: const Offset(0, 20),
                        spreadRadius: 4,
                      ),
                      BoxShadow(
                        color: const Color(0xFF14B8A6).withValues(alpha: 0.2),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BrandLogo(size: 64, showGlow: true),
                      const SizedBox(height: 24),
                      Text(
                        'SecureWave',
                        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.0,
                              fontSize: 42,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
                        ),
                        child: Text(
                          'v4.0',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Fast, private access powered by the SecureWave app.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                              height: 1.6,
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 32),
                      PrimaryButton(
                        label: 'Sign in',
                        icon: Icons.login,
                        onPressed: () => context.go('/login'),
                      ),
                      const SizedBox(height: 14),
                      SecondaryButton(
                        label: 'Create free account',
                        icon: Icons.person_add_outlined,
                        onPressed: () => context.go('/register'),
                      ),
                      const SizedBox(height: 28),
                      ResponsiveWrap(
                        minItemWidth: 130,
                        spacing: 12,
                        runSpacing: 12,
                        children: const [
                          _QuickChip(label: 'Fast setup', icon: Icons.bolt),
                          _QuickChip(label: 'Auto-connect', icon: Icons.shield),
                          _QuickChip(label: 'Free tier', icon: Icons.data_usage),
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
                  subtitle: 'Privacy-first policy. Your data stays yours.',
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
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.18), width: 2),
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.04),
              color.withValues(alpha: 0.02),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.18),
                      color.withValues(alpha: 0.12),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                            height: 1.5,
                            fontSize: 15,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 10),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
          ),
        ],
      ),
    );
  }
}

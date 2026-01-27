import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../ui/app_ui_v1.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppUIv1.space5),
          children: [
            Row(
              children: [
                SvgPicture.asset(
                  'assets/securewave_logo.svg',
                  width: 48,
                  height: 48,
                ),
                const SizedBox(width: AppUIv1.space3),
                Text('SecureWave', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: AppUIv1.space5),
            Text(
              'Calm protection in one tap.',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppUIv1.space2),
            Text(
              'Use the app to connect. The website and app work together to keep your account and connection simple.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppUIv1.space5),
            FilledButton.icon(
              onPressed: () => context.go('/login'),
              icon: const Icon(Icons.login),
              label: const Text('Sign in'),
            ),
            const SizedBox(height: AppUIv1.space3),
            OutlinedButton.icon(
              onPressed: () => context.go('/register'),
              icon: const Icon(Icons.person_add),
              label: const Text('Create account'),
            ),
            const SizedBox(height: AppUIv1.space6),
            Text('How it works', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppUIv1.space3),
            const _StepCard(
              icon: Icons.person_add,
              title: 'Create an account',
              description: 'Get started in under a minute.',
            ),
            const SizedBox(height: AppUIv1.space3),
            const _StepCard(
              icon: Icons.download,
              title: 'Download the app',
              description: 'Install SecureWave on desktop or mobile.',
            ),
            const SizedBox(height: AppUIv1.space3),
            const _StepCard(
              icon: Icons.shield,
              title: 'Tap connect',
              description: 'SecureWave handles regions and settings for you.',
            ),
            const SizedBox(height: AppUIv1.space6),
            Text('Why people choose SecureWave', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppUIv1.space3),
            const _FeatureCard(
              title: 'Clear status',
              description: 'Always know if you are protected.',
            ),
            const SizedBox(height: AppUIv1.space3),
            const _FeatureCard(
              title: 'Friendly guidance',
              description: 'Step-by-step diagnostics when something feels off.',
            ),
            const SizedBox(height: AppUIv1.space3),
            const _FeatureCard(
              title: 'Reliable routing',
              description: 'Smart region selection keeps the connection stable.',
            ),
          ],
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.icon, required this.title, required this.description});

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppUIv1.space4),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppUIv1.accentSoft,
              child: Icon(icon, color: AppUIv1.accentStrong),
            ),
            const SizedBox(width: AppUIv1.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppUIv1.space1),
                  Text(description, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppUIv1.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppUIv1.space2),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

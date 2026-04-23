import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ui/app_ui_v1.dart';
import '../../ui/securewave_ui.dart';
import 'auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

    return Scaffold(
      body: SwPage(
        safeArea: false,
        maxWidth: AppUIv1.authMaxWidth,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth > 820;
            final form = _LoginForm(
              formKey: _formKey,
              emailController: _emailController,
              passwordController: _passwordController,
              isLoading: state.isLoading,
              errorMessage: state.errorMessage,
              onSubmit: _submit,
            );
            if (!wide) {
              return ListView(
                padding: const EdgeInsets.symmetric(vertical: AppUIv1.space7),
                children: [
                  const _AuthHero(compact: true),
                  const SizedBox(height: AppUIv1.space5),
                  form,
                ],
              );
            }
            return Center(
              child: Row(
                children: [
                  const Expanded(child: _AuthHero()),
                  const SizedBox(width: AppUIv1.space6),
                  SizedBox(width: AppUIv1.authPanelWidth, child: form),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authControllerProvider.notifier).login(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
    if (!mounted) return;
    if (ref.read(authControllerProvider).errorMessage == null) {
      context.go('/vpn');
    }
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.isLoading,
    required this.onSubmit,
    this.errorMessage,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SwPanel(
      accent: AppUIv1.accentCyan,
      padding: const EdgeInsets.all(AppUIv1.space5),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SwBrandLockup(),
            const SizedBox(height: AppUIv1.space5),
            Text(
              'Welcome back',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppUIv1.space2),
            Text(
              'Secure access to your encrypted tunnel control plane.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppUIv1.space5),
            TextFormField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email address',
                hintText: 'you@example.com',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Enter your email.';
                if (!value.contains('@')) return 'Enter a valid email.';
                return null;
              },
            ),
            const SizedBox(height: AppUIv1.space4),
            TextFormField(
              controller: passwordController,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {
                if (!isLoading) onSubmit();
              },
              decoration: const InputDecoration(
                labelText: 'Password',
                hintText: 'Enter your password',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Enter your password.';
                }
                if (value.length < 8) return 'Use at least 8 characters.';
                return null;
              },
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: AppUIv1.space3),
              SwStatusPill(
                label: errorMessage!,
                color: AppUIv1.warning,
                icon: Icons.warning_amber_rounded,
              ),
            ],
            const SizedBox(height: AppUIv1.space5),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isLoading ? null : onSubmit,
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login_rounded),
                label: Text(isLoading ? 'Authenticating' : 'Sign in'),
              ),
            ),
            const SizedBox(height: AppUIv1.space3),
            Center(
              child: TextButton(
                onPressed: () => context.push('/register'),
                child: const Text('Create an account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthHero extends StatelessWidget {
  const _AuthHero({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SwReveal(
      child: Column(
        crossAxisAlignment:
            compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SwStatusPill(
            label: 'WireGuard-first secure access',
            color: AppUIv1.accentTeal,
            icon: Icons.verified_user_outlined,
            pulse: true,
          ),
          const SizedBox(height: AppUIv1.space5),
          Text(
            'Private by design.\nPrecise by default.',
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: AppUIv1.space4),
          Text(
            'A dark, audited control surface for encrypted desktop tunneling, diagnostics, and account operations.',
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: AppUIv1.space5),
          Wrap(
            spacing: AppUIv1.space3,
            runSpacing: AppUIv1.space3,
            alignment: compact ? WrapAlignment.center : WrapAlignment.start,
            children: const [
              _HeroStat(icon: Icons.shield_outlined, label: 'No fake status'),
              _HeroStat(icon: Icons.dns_outlined, label: 'DNS aware'),
              _HeroStat(
                icon: Icons.monitor_heart_outlined,
                label: 'Diagnostics',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SwPanel(
      padding: const EdgeInsets.symmetric(
        horizontal: AppUIv1.space3,
        vertical: AppUIv1.space2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppUIv1.accentCyan, size: 16),
          const SizedBox(width: AppUIv1.space2),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

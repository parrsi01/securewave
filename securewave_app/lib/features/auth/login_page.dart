import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../ui/components/dashboard_card.dart';
import '../../ui/layout/adaptive_shell_scaffold.dart';
import '../../ui/theme/spacing.dart';
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

    return AdaptiveShellScaffold(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SvgPicture.asset(
                'assets/securewave_logo.svg',
                width: 72,
                height: 72,
              ),
              const SizedBox(height: SecureWaveSpacing.lg),
              Text('Welcome back',
                  style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: SecureWaveSpacing.sm),
              Text(
                'Sign in to launch the SecureWave dashboard and reconnect instantly.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: SecureWaveSpacing.xl),
              DashboardCard(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration:
                            const InputDecoration(labelText: 'Email address'),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Enter your email.';
                          }
                          if (!value.contains('@')) {
                            return 'Enter a valid email.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: SecureWaveSpacing.md),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration:
                            const InputDecoration(labelText: 'Password'),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Enter your password.';
                          }
                          if (value.length < 8) {
                            return 'Use at least 8 characters.';
                          }
                          return null;
                        },
                      ),
                      if (state.errorMessage != null) ...[
                        const SizedBox(height: SecureWaveSpacing.md),
                        Text(
                          state.errorMessage!,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                        ),
                      ],
                      const SizedBox(height: SecureWaveSpacing.lg),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: state.isLoading
                              ? null
                              : () async {
                                  if (!_formKey.currentState!.validate()) {
                                    return;
                                  }
                                  await ref
                                      .read(authControllerProvider.notifier)
                                      .login(
                                        email: _emailController.text.trim(),
                                        password:
                                            _passwordController.text.trim(),
                                      );
                                  if (!context.mounted) return;
                                  if (ref
                                          .read(authControllerProvider)
                                          .errorMessage ==
                                      null) {
                                    context.go('/vpn');
                                  }
                                },
                          child: state.isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Sign in'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: SecureWaveSpacing.md),
              Center(
                child: TextButton(
                  onPressed: () => context.push('/register'),
                  child: const Text('Create an account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

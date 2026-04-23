import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ui/app_ui_v1.dart';
import '../../ui/securewave_ui.dart';
import 'auth_controller.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

    return Scaffold(
      body: SwPage(
        safeArea: false,
        maxWidth: AppUIv1.authMaxWidth,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppUIv1.authPanelWidth),
            child: SwPanel(
              accent: AppUIv1.accentTeal,
              padding: const EdgeInsets.all(AppUIv1.space5),
              child: Form(
                key: _formKey,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    const SwBrandLockup(),
                    const SizedBox(height: AppUIv1.space5),
                    Text(
                      'Create secure access',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppUIv1.space2),
                    Text(
                      'Register an account for SecureWave tunnel provisioning and plan management.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppUIv1.space5),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        hintText: 'you@example.com',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Enter your email.';
                        }
                        if (!value.contains('@')) return 'Enter a valid email.';
                        return null;
                      },
                    ),
                    const SizedBox(height: AppUIv1.space4),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        hintText: 'Create a password',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Create a password.';
                        }
                        if (value.length < 8) {
                          return 'Use at least 8 characters.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppUIv1.space4),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (!state.isLoading) _submit();
                      },
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                        hintText: 'Repeat your password',
                        prefixIcon: Icon(Icons.verified_user_outlined),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Confirm your password.';
                        }
                        if (value != _passwordController.text) {
                          return 'Passwords do not match.';
                        }
                        return null;
                      },
                    ),
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: AppUIv1.space3),
                      SwStatusPill(
                        label: state.errorMessage!,
                        color: AppUIv1.warning,
                        icon: Icons.warning_amber_rounded,
                      ),
                    ],
                    const SizedBox(height: AppUIv1.space5),
                    FilledButton.icon(
                      onPressed: state.isLoading ? null : _submit,
                      icon: state.isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.person_add_alt_1_rounded),
                      label: Text(
                        state.isLoading ? 'Creating account' : 'Create account',
                      ),
                    ),
                    const SizedBox(height: AppUIv1.space3),
                    Center(
                      child: TextButton(
                        onPressed: () {
                          if (Navigator.of(context).canPop()) {
                            context.pop();
                            return;
                          }
                          context.go('/login');
                        },
                        child: const Text('Already have an account? Sign in'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authControllerProvider.notifier).register(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
    if (!mounted) return;
    if (ref.read(authControllerProvider).errorMessage == null) {
      context.go('/vpn');
    }
  }
}

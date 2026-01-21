import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../widgets/buttons/primary_button.dart';
import '../../widgets/cards/status_chip.dart';
import '../../widgets/layouts/app_background.dart';
import '../../widgets/layouts/content_layout.dart';
import '../../widgets/layouts/section_header.dart';
import '../../widgets/loaders/inline_banner.dart';
import 'auth_controller.dart';
import '../../core/theme/app_assets.dart';

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
  bool _hasTyped = false;

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
      body: AppBackground(
        child: SafeArea(
          child: ContentLayout(
            child: ListView(
              children: [
                SvgPicture.asset(AppAssets.logo, height: 64),
                const SizedBox(height: 16),
                const StatusChip(label: 'Start free', color: Color(0xFF4F46E5)),
                const SizedBox(height: 16),
                const SectionHeader(
                  title: 'Create your account',
                  subtitle: 'Provision devices and connect using the SecureWave app.',
                ),
                const SizedBox(height: 24),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      autovalidateMode:
                          _hasTyped ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _emailController,
                            decoration: const InputDecoration(labelText: 'Email'),
                            keyboardType: TextInputType.emailAddress,
                            onChanged: (_) => setState(() => _hasTyped = true),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Enter your email';
                              if (!value.contains('@')) return 'Enter a valid email';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            decoration: const InputDecoration(labelText: 'Password'),
                            obscureText: true,
                            onChanged: (_) => setState(() => _hasTyped = true),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Create a password';
                              if (value.length < 8) return 'Minimum 8 characters';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmController,
                            decoration: const InputDecoration(labelText: 'Confirm password'),
                            obscureText: true,
                            onChanged: (_) => setState(() => _hasTyped = true),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Confirm your password';
                              if (value != _passwordController.text) return 'Passwords do not match';
                              return null;
                            },
                          ),
                          if (state.errorMessage != null) ...[
                            const SizedBox(height: 16),
                            InlineBanner(message: state.errorMessage!),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Create account',
                  isLoading: state.isLoading,
                  onPressed: () async {
                    setState(() => _hasTyped = true);
                    if (!_formKey.currentState!.validate()) return;
                    await ref.read(authControllerProvider.notifier).register(
                          email: _emailController.text.trim(),
                          password: _passwordController.text.trim(),
                        );
                    if (mounted && ref.read(authControllerProvider).errorMessage == null) {
                      context.go('/dashboard');
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Already have an account? Sign in'),
                ),
                const SizedBox(height: 8),
                Text(
                  'SecureWave provisions your device and connects through the native app.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

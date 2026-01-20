import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../widgets/buttons/primary_button.dart';
import '../../widgets/cards/status_chip.dart';
import '../../widgets/layouts/content_layout.dart';
import '../../widgets/layouts/section_header.dart';
import '../../widgets/loaders/inline_banner.dart';
import 'auth_controller.dart';
import '../../core/theme/app_assets.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _hasTyped = false;

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
      body: SafeArea(
        child: ContentLayout(
          child: ListView(
            children: [
              SvgPicture.asset(AppAssets.logo, height: 64),
              const SizedBox(height: 16),
              const StatusChip(label: 'Secure sign-in', color: Color(0xFF38BDF8)),
              const SizedBox(height: 16),
              const SectionHeader(
                title: 'Welcome back',
                subtitle: 'Sign in to manage your devices, servers, and VPN access.',
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
                            if (value == null || value.isEmpty) return 'Enter your password';
                            if (value.length < 8) return 'Minimum 8 characters';
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
                label: 'Continue',
                isLoading: state.isLoading,
                onPressed: () async {
                  setState(() => _hasTyped = true);
                  if (!_formKey.currentState!.validate()) return;
                  await ref.read(authControllerProvider.notifier).login(
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
                onPressed: () => context.go('/register'),
                child: const Text('Create an account'),
              ),
              const SizedBox(height: 8),
              Text(
                'SecureWave uses OS-level WireGuard tunnels. The app only manages your access.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

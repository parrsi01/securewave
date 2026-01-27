import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../ui/app_ui_v1.dart';
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppUIv1.space5),
          children: [
            SvgPicture.asset(
              'assets/securewave_logo.svg',
              width: 56,
              height: 56,
            ),
            const SizedBox(height: AppUIv1.space4),
            Text('Welcome back', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: AppUIv1.space2),
            Text(
              'Sign in to connect and manage your SecureWave account.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppUIv1.space5),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppUIv1.space4),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Email address', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: AppUIv1.space2),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(hintText: 'you@example.com'),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Enter your email.';
                          if (!value.contains('@')) return 'Enter a valid email.';
                          return null;
                        },
                      ),
                      const SizedBox(height: AppUIv1.space4),
                      Text('Password', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: AppUIv1.space2),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(hintText: 'Enter your password'),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Enter your password.';
                          if (value.length < 8) return 'Use at least 8 characters.';
                          return null;
                        },
                      ),
                      if (state.errorMessage != null) ...[
                        const SizedBox(height: AppUIv1.space3),
                        Text(
                          state.errorMessage!,
                          style: const TextStyle(color: AppUIv1.warning),
                        ),
                      ],
                      const SizedBox(height: AppUIv1.space4),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: state.isLoading
                              ? null
                              : () async {
                                  if (!_formKey.currentState!.validate()) return;
                                  await ref.read(authControllerProvider.notifier).login(
                                        email: _emailController.text.trim(),
                                        password: _passwordController.text.trim(),
                                      );
                                  if (!context.mounted) return;
                                  if (ref.read(authControllerProvider).errorMessage == null) {
                                    context.go('/vpn');
                                  }
                                },
                          child: state.isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Sign in'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppUIv1.space4),
            Center(
              child: TextButton(
                onPressed: () => context.go('/register'),
                child: const Text('Create an account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

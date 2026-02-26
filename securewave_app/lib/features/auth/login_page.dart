import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../ui/design/app_colors.dart';
import '../../ui/design/app_spacing.dart';
import 'auth_controller.dart';
import 'auth_widgets.dart';

/// Login page — v2.
///
/// Split-layout: teal gradient top half with logo + tagline,
/// form content in the bottom half.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final config = ref.read(appConfigProvider);
    if (_emailController.text.isEmpty &&
        (config.devLoginEmail ?? '').trim().isNotEmpty) {
      _emailController.text = config.devLoginEmail!.trim();
    }
    if (_passwordController.text.isEmpty &&
        (config.devLoginPassword ?? '').isNotEmpty) {
      _passwordController.text = config.devLoginPassword!;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Gradient header ────────────────────────────────────────
            const AuthHeader(
              headline: 'Welcome back',
              subline: 'Secure. Private. Always on.',
            ),

            // ── Form ───────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: AppSpacing.authMaxWidth),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.space4,
                        AppSpacing.space5,
                        AppSpacing.space4,
                        AppSpacing.space4,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const AuthFieldLabel('Email address'),
                            const SizedBox(height: AppSpacing.space2),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                hintText: 'you@example.com',
                                prefixIcon: Icon(Icons.mail_outline_rounded),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Enter your email.';
                                }
                                if (!v.contains('@')) {
                                  return 'Enter a valid email.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: AppSpacing.space4),
                            const AuthFieldLabel('Password'),
                            const SizedBox(height: AppSpacing.space2),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              decoration: InputDecoration(
                                hintText: 'Enter your password',
                                prefixIcon:
                                    const Icon(Icons.lock_outline_rounded),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    size: AppSpacing.iconS,
                                  ),
                                  onPressed: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Enter your password.';
                                }
                                if (v.length < 8) {
                                  return 'Use at least 8 characters.';
                                }
                                return null;
                              },
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            if (state.errorMessage != null) ...[
                              const SizedBox(height: AppSpacing.space3),
                              AuthErrorBanner(message: state.errorMessage!),
                            ],
                            const SizedBox(height: AppSpacing.space5),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: state.isLoading ? null : _submit,
                                child: state.isLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Sign In'),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.space4),
                            Center(
                              child: TextButton(
                                onPressed: () => context.push('/register'),
                                child: RichText(
                                  text: TextSpan(
                                    text: "Don't have an account? ",
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                    children: [
                                      TextSpan(
                                        text: 'Create one',
                                        style: TextStyle(
                                          color: isDark
                                              ? AppColors.primaryBright
                                              : AppColors.primary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
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
      context.go('/home');
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../debug/automation_keys.dart';
import '../../features/auth/auth_controller.dart';
import '../theme/securewave_palette.dart';
import '../widgets/auth_shell.dart';

class RegisterScreen extends HookConsumerWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final emailController = useTextEditingController();
    final passwordController = useTextEditingController();
    final confirmController = useTextEditingController();
    final obscurePassword = useState(true);
    final obscureConfirm = useState(true);

    Future<void> submit() async {
      if (!formKey.currentState!.validate()) return;
      await ref.read(authControllerProvider.notifier).register(
            email: emailController.text.trim(),
            password: passwordController.text,
          );
      if (!context.mounted) return;
      if (ref.read(authControllerProvider).errorMessage == null) {
        context.go('/home');
      }
    }

    return Scaffold(
      body: AuthShell(
        title: 'Create account',
        subtitle:
            'Provision a SecureWave account and make diagnostics, server selection, and VPN control available immediately.',
        child: Form(
          key: formKey,
          child: Column(
            children: <Widget>[
              TextFormField(
                key: const ValueKey<String>(AutomationKeys.registerEmailField),
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter your email.';
                  }
                  if (!value.contains('@')) {
                    return 'Enter a valid email.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey<String>(
                    AutomationKeys.registerPasswordField),
                controller: passwordController,
                obscureText: obscurePassword.value,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        obscurePassword.value = !obscurePassword.value,
                    icon: Icon(
                      obscurePassword.value
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
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
              const SizedBox(height: 16),
              TextFormField(
                key:
                    const ValueKey<String>(AutomationKeys.registerConfirmField),
                controller: confirmController,
                obscureText: obscureConfirm.value,
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        obscureConfirm.value = !obscureConfirm.value,
                    icon: Icon(
                      obscureConfirm.value
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value != passwordController.text) {
                    return 'Passwords do not match.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => submit(),
              ),
              if (auth.errorMessage != null) ...<Widget>[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    auth.errorMessage!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: SecureWavePalette.danger,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey<String>(
                      AutomationKeys.registerSubmitButton),
                  onPressed: auth.isLoading ? null : submit,
                  child: auth.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create account'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const ValueKey<String>(
                    AutomationKeys.registerBackToLoginButton,
                  ),
                  onPressed: () => context.go('/login'),
                  child: const Text('Back to sign in'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

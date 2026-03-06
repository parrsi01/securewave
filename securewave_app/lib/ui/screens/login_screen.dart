import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../debug/automation_keys.dart';
import '../../features/auth/auth_controller.dart';
import '../theme/securewave_palette.dart';
import '../widgets/auth_shell.dart';

class LoginScreen extends HookConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final formKey = useMemoized(GlobalKey<FormState>.new);
    final emailController = useTextEditingController();
    final passwordController = useTextEditingController();
    final obscure = useState(true);

    Future<void> submit() async {
      if (!formKey.currentState!.validate()) return;
      await ref.read(authControllerProvider.notifier).login(
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
        title: 'Sign in',
        subtitle:
            'Restore your SecureWave session and return to the VPN control surface.',
        child: Form(
          key: formKey,
          child: Column(
            children: <Widget>[
              TextFormField(
                key: const ValueKey<String>(AutomationKeys.loginEmailField),
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
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
                key: const ValueKey<String>(AutomationKeys.loginPasswordField),
                controller: passwordController,
                obscureText: obscure.value,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    onPressed: () => obscure.value = !obscure.value,
                    icon: Icon(
                      obscure.value
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
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
                  key: const ValueKey<String>(AutomationKeys.loginSubmitButton),
                  onPressed: auth.isLoading ? null : submit,
                  child: auth.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign in'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const ValueKey<String>(
                    AutomationKeys.loginCreateAccountButton,
                  ),
                  onPressed: () => context.push('/register'),
                  child: const Text('Create account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

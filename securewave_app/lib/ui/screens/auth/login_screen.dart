import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/colors.dart';
import '../../../debug/automation_keys.dart';
import '../../../features/auth/auth_controller.dart';
import '../../../features/auth/auth_widgets.dart';
import '../../../ui/components/neon_button.dart';
import '../../../ui/components/htb_background.dart';
import '../../../ui/design/app_spacing.dart';
import '../../../ui/theme/app_colors.dart' as htb;
import '../../../ui/widgets/glass_panel.dart';

/// Login screen.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = ref.read(authControllerProvider.notifier);
    await auth.login(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      backgroundColor: htb.HtbColors.bg0,
      body: Stack(
        children: [
          const HtbBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final formCard =GlassPanel(
                  glowColor: htb.HtbColors.accentSecondaryMuted,
                  borderColor: htb.HtbColors.accentSecondaryGhost,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (authState.errorMessage != null) ...[
                        AuthErrorBanner(message: authState.errorMessage!),
                        const SizedBox(height: AppSpacing.space4),
                      ],
                      const AuthFieldLabel('Email'),
                      const SizedBox(height: AppSpacing.space2),
                      TextFormField(
                        key: AutomationKeys.loginEmailFieldKey,
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          hintText: 'you@example.com',
                          prefixIcon: Icon(Icons.mail_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space4),
                      const AuthFieldLabel('Password'),
                      const SizedBox(height: AppSpacing.space2),
                      TextFormField(
                        key: AutomationKeys.loginPasswordFieldKey,
                        controller: _passwordCtrl,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          hintText:
                              '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space6),
                      NeonButton(
                        key: AutomationKeys.loginSubmitButtonKey,
                        width: double.infinity,
                        label: 'Sign In',
                        icon: Icons.login_rounded,
                        isConnecting: authState.isLoading,
                        onPressed: authState.isLoading ? null : _submit,
                      ),
                      const SizedBox(height: AppSpacing.space4),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            "Don't have an account?",
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          TextButton(
                            key: AutomationKeys.loginCreateAccountButtonKey,
                            onPressed: () => context.go('/register'),
                            style: TextButton.styleFrom(
                              foregroundColor: htb.HtbColors.accentSecondary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.space2,
                              ),
                            ),
                            child: const Text(
                              'Register',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );

                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.pagePadding,
                      vertical: AppSpacing.space5,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppSpacing.authMaxWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryDeep,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: AppColors.primary.withValues(alpha: 0.35),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: SvgPicture.asset('assets/securewave_logo.svg'),
                                ),
                                const SizedBox(width: 14),
                                const Text(
                                  'SecureWave',
                                  style: TextStyle(
                                    fontFamily: 'JetBrainsMono',
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          formCard,
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

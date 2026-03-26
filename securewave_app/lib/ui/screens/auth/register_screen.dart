import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../debug/automation_keys.dart';
import '../../../features/auth/auth_controller.dart';
import '../../../features/auth/auth_widgets.dart';
import '../../../services/auth_service.dart';
import '../../../ui/components/neon_button.dart';
import '../../../ui/components/htb_background.dart';
import '../../../ui/design/app_spacing.dart';
import '../../../ui/theme/app_colors.dart' as htb;
import '../../../ui/widgets/glass_panel.dart';

/// Registration screen.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  String? _localError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_passwordCtrl.text != _confirmCtrl.text) {
      setState(() => _localError = 'Passwords do not match.');
      return;
    }
    setState(() => _localError = null);
    final auth = ref.read(authControllerProvider.notifier);
    final outcome = await auth.register(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    );
    if (!mounted || outcome == null) return;
    if (outcome == RegistrationOutcome.loginRequired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created. Sign in to continue.')),
      );
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final errorMsg = _localError ?? authState.errorMessage;

    return Scaffold(
      backgroundColor: htb.HtbColors.bg0,
      body: Stack(
        children: [
          const HtbBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 980;
                final formCard = GlassPanel(
                  glowColor: htb.HtbColors.accentSecondaryMuted,
                  borderColor: htb.HtbColors.accentSecondaryGhost,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (errorMsg != null) ...[
                        AuthErrorBanner(message: errorMsg),
                        const SizedBox(height: AppSpacing.space4),
                      ],
                      const AuthFieldLabel('Email'),
                      const SizedBox(height: AppSpacing.space2),
                      TextFormField(
                        key: AutomationKeys.registerEmailFieldKey,
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
                        key: AutomationKeys.registerPasswordFieldKey,
                        controller: _passwordCtrl,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.newPassword],
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
                      const SizedBox(height: AppSpacing.space4),
                      const AuthFieldLabel('Confirm Password'),
                      const SizedBox(height: AppSpacing.space2),
                      TextFormField(
                        key: AutomationKeys.registerConfirmFieldKey,
                        controller: _confirmCtrl,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.newPassword],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          hintText:
                              '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space6),
                      NeonButton(
                        key: AutomationKeys.registerSubmitButtonKey,
                        width: double.infinity,
                        label: 'Create Account',
                        icon: Icons.arrow_outward_rounded,
                        isConnecting: authState.isLoading,
                        onPressed: authState.isLoading ? null : _submit,
                      ),
                      const SizedBox(height: AppSpacing.space4),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Already have an account?',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          TextButton(
                            key: AutomationKeys.registerBackToLoginButtonKey,
                            onPressed: () => context.go('/login'),
                            style: TextButton.styleFrom(
                              foregroundColor: htb.HtbColors.accentSecondary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.space2,
                              ),
                            ),
                            child: const Text(
                              'Sign In',
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
                      constraints: BoxConstraints(
                        maxWidth: isWide ? 1080 : AppSpacing.authMaxWidth,
                      ),
                      child: isWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Expanded(
                                  flex: 11,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      AuthHeader(
                                        headline: 'Create account',
                                        subline: 'Join SecureWave',
                                      ),
                                      SizedBox(height: AppSpacing.space4),
                                      AuthFeaturePanel(
                                        kicker: 'ONBOARDING NODE',
                                        title:
                                            'Launch a cleaner security workspace',
                                        description:
                                            'Create your SecureWave identity and move straight into connection controls, diagnostics, and account management.',
                                        items: [
                                          'Unified control surfaces across mobile and desktop',
                                          'Fast auth flow with minimal visual noise',
                                          'Built-in diagnostics and health monitoring after sign-in',
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.space5),
                                Expanded(flex: 9, child: formCard),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const AuthHeader(
                                  headline: 'Create account',
                                  subline: 'Join SecureWave',
                                ),
                                const SizedBox(height: AppSpacing.space4),
                                const AuthFeaturePanel(
                                  kicker: 'ONBOARDING NODE',
                                  title: 'Launch a cleaner security workspace',
                                  description:
                                      'Create your SecureWave identity and move straight into connection controls, diagnostics, and account management.',
                                  items: [
                                    'Unified control surfaces across mobile and desktop',
                                    'Built-in diagnostics and health monitoring after sign-in',
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.space4),
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

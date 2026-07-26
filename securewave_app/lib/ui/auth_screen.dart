part of '../app.dart';

class _AuthScreen extends ConsumerStatefulWidget {
  const _AuthScreen({
    this.initialRegister = false,
    this.initialMessage,
  });

  final bool initialRegister;
  final String? initialMessage;

  @override
  ConsumerState<_AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<_AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _resetToken = TextEditingController();
  bool _register = false;
  bool _forgotPassword = false;
  bool _resetRequested = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _register = widget.initialRegister;
    _error = widget.initialMessage;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _resetToken.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = _forgotPassword
        ? 'Request a reset email and choose a new SecureWave password.'
        : _register
            ? 'Create an account to start using SecureWave.'
            : 'Sign in to manage your VPN session.';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: _PlainPanel(
                padding: const EdgeInsets.all(22),
                child: Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'SecureWave',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          copy,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 22),
                        TextFormField(
                          controller: _email,
                          autofillHints: const [
                            AutofillHints.username,
                            AutofillHints.email,
                          ],
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email address',
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
                        if (_forgotPassword && _resetRequested) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _resetToken,
                            decoration: const InputDecoration(
                              labelText: 'Reset token',
                              helperText:
                                  'Paste the token from the reset link.',
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Enter the reset token.'
                                    : null,
                          ),
                        ],
                        if (!_forgotPassword || _resetRequested) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: _hidePassword,
                            autofillHints: [
                              _register
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            textInputAction: _register
                                ? TextInputAction.next
                                : TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: _forgotPassword
                                  ? 'New SecureWave password'
                                  : 'Password',
                              suffixIcon: IconButton(
                                tooltip: _hidePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                icon: Icon(
                                  _hidePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () {
                                  setState(
                                      () => _hidePassword = !_hidePassword);
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Enter your password.';
                              }
                              if (value.length < 8) {
                                return 'Use at least 8 characters.';
                              }
                              if (!RegExp(r'[A-Za-z]').hasMatch(value) ||
                                  !RegExp(r'[0-9]').hasMatch(value) ||
                                  !RegExp(r'[^A-Za-z0-9]').hasMatch(value)) {
                                return 'Use letters, numbers, and a special character.';
                              }
                              return null;
                            },
                          ),
                        ],
                        if (_register ||
                            (_forgotPassword && _resetRequested)) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _confirm,
                            obscureText: true,
                            autofillHints: const [AutofillHints.newPassword],
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Confirm password',
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Confirm your password.';
                              }
                              if (value != _password.text) {
                                return 'Passwords do not match.';
                              }
                              return null;
                            },
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          _InlineMessage(
                            icon: Icons.warning_amber_rounded,
                            message: _error!,
                            tone: _Tone.error,
                            actionLabel: 'Dismiss',
                            onAction: () => setState(() => _error = null),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(_forgotPassword
                                  ? (_resetRequested
                                      ? 'Set new password'
                                      : 'Send reset email')
                                  : (_register ? 'Create account' : 'Sign in')),
                        ),
                        const SizedBox(height: 8),
                        if (!_register)
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    setState(() {
                                      _forgotPassword = !_forgotPassword;
                                      _resetRequested = false;
                                      _error = null;
                                      _password.clear();
                                      _confirm.clear();
                                      _resetToken.clear();
                                    });
                                  },
                            child: Text(_forgotPassword
                                ? 'Back to sign in'
                                : 'Forgot password?'),
                          ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  setState(() {
                                    _forgotPassword = false;
                                    _resetRequested = false;
                                    _register = !_register;
                                    _error = null;
                                  });
                                },
                          child: Text(
                            _forgotPassword
                                ? 'Use an existing account'
                                : _register
                                    ? 'Use an existing account'
                                    : 'Create a new account',
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
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final auth = ref.read(authServiceProvider);
      if (_forgotPassword) {
        final api = ref.read(apiClientProvider);
        if (!_resetRequested) {
          await api.requestPasswordReset(email: _email.text.trim());
          if (mounted) {
            setState(() => _resetRequested = true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content:
                      Text('If the email exists, a reset link has been sent.')),
            );
          }
        } else {
          await api.confirmPasswordReset(
            token: _resetToken.text.trim(),
            newPassword: _password.text,
          );
          if (mounted) {
            setState(() {
              _forgotPassword = false;
              _resetRequested = false;
              _password.clear();
              _confirm.clear();
              _resetToken.clear();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Password updated. You can now sign in.')),
            );
          }
        }
      } else if (_register) {
        await auth.register(
          email: _email.text.trim(),
          password: _password.text.trim(),
        );
      } else {
        await auth.login(
          email: _email.text.trim(),
          password: _password.text.trim(),
        );
      }
      ref.read(bootControllerProvider).markSessionAuthenticated();
      ref.invalidate(currentUserProvider);
      ref.invalidate(userPlanProvider);
      ref.invalidate(serversProvider);
    } catch (error, stackTrace) {
      AppLogger.error('Auth form failed', error: error, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _error = ApiError.messageFrom(
          error,
          fallback: _register
              ? 'We could not create your account. Please try again.'
              : 'We could not sign you in. Check your details and try again.',
        );
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

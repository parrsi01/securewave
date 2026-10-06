import 'package:flutter/material.dart';

import 'theme.dart';

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'SecureWave',
        excludeSemantics: true,
        child: Text.rich(TextSpan(children: [
          TextSpan(text: 'Secure', style: AppTheme.wordmark),
          TextSpan(
              text: 'Wave',
              style: AppTheme.wordmark.copyWith(color: AppTheme.accentPrimary)),
        ])),
      );
}

class UiFeedback extends StatelessWidget {
  const UiFeedback(this.message, {super.key, this.isError = true});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppTheme.error : AppTheme.accentPrimary;
    return Semantics(
      liveRegion: true,
      child: AnimatedContainer(
        duration: AppTheme.reduceMotion(context)
            ? Duration.zero
            : AppTheme.stateDuration,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfacePrimary,
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ExcludeSemantics(
              child: Icon(isError ? Icons.error_outline : Icons.info_outline,
                  size: 20, color: color)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(message,
                  style: AppTheme.smallBody
                      .copyWith(color: AppTheme.textPrimary))),
        ]),
      ),
    );
  }
}

class BootView extends StatelessWidget {
  const BootView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const BrandWordmark(),
                const SizedBox(height: 24),
                if (AppTheme.reduceMotion(context))
                  const Icon(Icons.hourglass_empty,
                      size: 20, color: AppTheme.accentPrimary)
                else
                  const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(height: 16),
                Text('Restoring your session…', style: AppTheme.smallBody),
              ]),
            ),
          ),
        ),
      );
}

/// Layout only: fields, validation and submission stay with the auth owner.
class AuthForm extends StatelessWidget {
  const AuthForm({
    super.key,
    required this.formKey,
    required this.fields,
    required this.registering,
    required this.busy,
    required this.onSubmit,
    required this.onSwitchMode,
    this.error,
    this.notice,
  });

  final GlobalKey<FormState> formKey;
  final List<Widget> fields;
  final bool registering;
  final bool busy;
  final VoidCallback onSubmit;
  final VoidCallback onSwitchMode;
  final String? error;
  final String? notice;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            final padding = AppTheme.outerPadding(constraints.maxWidth);
            return SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - padding * 2)
                        .clamp(0, double.infinity)),
                child: Align(
                  alignment: constraints.maxHeight < 640
                      ? Alignment.topCenter
                      : Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: FocusTraversalGroup(
                      child: Form(
                        key: formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Align(
                                alignment: Alignment.centerLeft,
                                child: BrandWordmark()),
                            const SizedBox(height: 32),
                            Text(registering ? 'Create account' : 'Sign in',
                                style: AppTheme.pageTitle),
                            const SizedBox(height: 8),
                            Text(
                                registering
                                    ? 'Create your SecureWave account.'
                                    : 'Sign in to use SecureWave.',
                                style: AppTheme.smallBody),
                            const SizedBox(height: 24),
                            ...fields,
                            if (error != null) ...[
                              const SizedBox(height: 16),
                              UiFeedback(error!.contains('(HTTP ')
                                  ? 'SecureWave could not complete that request.'
                                  : error!),
                            ],
                            if (notice != null) ...[
                              const SizedBox(height: 16),
                              UiFeedback(notice!, isError: false),
                            ],
                            const SizedBox(height: 24),
                            FilledButton(
                              key: const ValueKey('auth-submit'),
                              clipBehavior: Clip.none,
                              style: ButtonStyle(
                                  animationDuration:
                                      AppTheme.reduceMotion(context)
                                          ? Duration.zero
                                          : AppTheme.interactionDuration),
                              onPressed: busy ? null : onSubmit,
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  if (busy)
                                    if (AppTheme.reduceMotion(context))
                                      const Icon(Icons.hourglass_empty,
                                          size: 18)
                                    else
                                      const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2)),
                                  Text(busy
                                      ? registering
                                          ? 'Creating account…'
                                          : 'Signing in…'
                                      : registering
                                          ? 'Create account'
                                          : 'Sign in'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: busy ? null : onSwitchMode,
                              child: Text(
                                registering
                                    ? 'Already have an account? Sign in'
                                    : 'New to SecureWave? Create an account',
                                textAlign: TextAlign.center,
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
          }),
        ),
      );
}

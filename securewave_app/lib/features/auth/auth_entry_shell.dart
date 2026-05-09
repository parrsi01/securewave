import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../ui/app_ui_v1.dart';

class AuthEntryShell extends StatelessWidget {
  const AuthEntryShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.formTitle,
    required this.formSubtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final String formTitle;
  final String formSubtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SecurePageBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final padding = AppUIv1.pagePaddingFor(width);
              final isCompact = AppUIv1.isCompactWidth(width);
              final shellWidth = isCompact ? AppUIv1.authMaxWidth : 520.0;
              final minHeight = constraints.maxHeight > padding.vertical
                  ? constraints.maxHeight - padding.vertical
                  : 0.0;

              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: padding,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: Center(
                    child: _AuthEntryMotion(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: shellWidth),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _AuthBrandHeader(
                              title: title,
                              subtitle: subtitle,
                              compact: isCompact,
                            ),
                            SizedBox(
                              height:
                                  isCompact ? AppUIv1.space5 : AppUIv1.space6,
                            ),
                            SecureSurface(
                              variant: SecureSurfaceVariant.glass,
                              padding: EdgeInsets.all(
                                isCompact ? AppUIv1.space4 : AppUIv1.space5,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    formTitle,
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: AppUIv1.space1),
                                  Text(
                                    formSubtitle,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: AppUIv1.space5),
                                  ...children,
                                ],
                              ),
                            ),
                            const SizedBox(height: AppUIv1.space4),
                            Text(
                              'Linux desktop release candidate',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppUIv1.inkSoft),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class SecureAuthTextField extends StatefulWidget {
  const SecureAuthTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.autofillHints,
    this.suffixIcon,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final Iterable<String>? autofillHints;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  @override
  State<SecureAuthTextField> createState() => _SecureAuthTextFieldState();
}

class _SecureAuthTextFieldState extends State<SecureAuthTextField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focusNode.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppUIv1.space2),
        AnimatedContainer(
          duration: AppUIv1.durationFast,
          curve: AppUIv1.curveDefault,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppUIv1.radiusM),
            boxShadow: focused ? AppUIv1.glowAccent : const [],
          ),
          child: TextFormField(
            focusNode: _focusNode,
            controller: widget.controller,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            obscureText: widget.obscureText,
            autofillHints: widget.autofillHints,
            decoration: InputDecoration(
              hintText: widget.hintText,
              suffixIcon: widget.suffixIcon,
            ),
            validator: widget.validator,
          ),
        ),
      ],
    );
  }
}

class SecureAuthPrimaryButton extends StatefulWidget {
  const SecureAuthPrimaryButton({
    super.key,
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final Future<void> Function()? onPressed;

  @override
  State<SecureAuthPrimaryButton> createState() =>
      _SecureAuthPrimaryButtonState();
}

class _SecureAuthPrimaryButtonState extends State<SecureAuthPrimaryButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;
    return MouseRegion(
      onEnter: (_) {
        if (enabled) setState(() => _hovered = true);
      },
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        duration: AppUIv1.durationFast,
        curve: AppUIv1.curveDefault,
        scale: _hovered && enabled ? 1.012 : 1,
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: enabled ? widget.onPressed : null,
            child: AnimatedSwitcher(
              duration: AppUIv1.durationFast,
              child: widget.isLoading
                  ? const SizedBox(
                      key: ValueKey('loading'),
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppUIv1.background),
                      ),
                    )
                  : Text(
                      widget.label,
                      key: ValueKey(widget.label),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SecureSurface(
      variant: SecureSurfaceVariant.danger,
      padding: const EdgeInsets.all(AppUIv1.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppUIv1.danger,
            size: 20,
          ),
          const SizedBox(width: AppUIv1.space2),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppUIv1.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthEntryMotion extends StatelessWidget {
  const _AuthEntryMotion({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppUIv1.durationSlow,
      curve: AppUIv1.curveDefault,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _AuthBrandHeader extends StatelessWidget {
  const _AuthBrandHeader({
    required this.title,
    required this.subtitle,
    required this.compact,
  });

  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: compact ? 72 : 82,
          height: compact ? 72 : 82,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppUIv1.surfaceGradient,
            border: Border.all(color: AppUIv1.borderStrong),
            boxShadow: AppUIv1.glowAccent,
          ),
          child: Center(
            child: SvgPicture.asset(
              'assets/securewave_logo.svg',
              width: compact ? 44 : 50,
              height: compact ? 44 : 50,
            ),
          ),
        ),
        const SizedBox(height: AppUIv1.space4),
        Text(
          'SecureWave',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppUIv1.space2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              color: AppUIv1.accentCyan,
              size: 17,
            ),
            const SizedBox(width: AppUIv1.space2),
            Flexible(
              child: Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: AppUIv1.accentCyan),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppUIv1.space2),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

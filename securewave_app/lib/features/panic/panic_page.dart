import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/auth_session.dart';
import '../../core/services/secure_storage.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../../ui/app_haptics.dart';
import '../../ui/app_ui_v1.dart';

class PanicPage extends ConsumerStatefulWidget {
  const PanicPage({super.key});

  @override
  ConsumerState<PanicPage> createState() => _PanicPageState();
}

class _PanicPageState extends ConsumerState<PanicPage> {
  bool _running = false;
  bool _done = false;
  String? _error;
  final List<_PanicStep> _steps = [];

  Future<void> _runPanic() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
      _steps.clear();
    });

    try {
      _addStep('Disconnecting VPN tunnel');
      await ref.read(vpnStateProvider.notifier).disconnect();
      _updateStep('VPN disconnected', true);

      _addStep('Clearing cached tunnel profile');
      final storage = SecureStorage();
      await storage.delete(SecureStorage.vpnProfileConfigKey);
      await storage.delete(SecureStorage.vpnProfileExpiresAtKey);
      _updateStep('Tunnel profile cleared', true);

      _addStep('Rotating server preference');
      await _rotateServerPreference();
      _updateStep('Server preference rotated', true);

      _addStep('Signing out and clearing tokens');
      await ref.read(authSessionProvider).clearSession();
      _updateStep('Signed out and tokens cleared', true);

      if (!mounted) return;
      setState(() => _done = true);
    } catch (e) {
      if (!mounted) return;
      _updateStep('Failed: ${e.toString()}', false);
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  Future<void> _rotateServerPreference() async {
    final storage = SecureStorage();
    final servers = ref.read(serversProvider);
    final currentServerId = ref.read(vpnStateProvider).selectedServerId;

    final serverList = servers.maybeWhen(
      data: (data) => data,
      orElse: () => null,
    );

    if (serverList != null && serverList.length > 1) {
      final rng = Random();
      final candidates =
          serverList.where((s) => s.id != currentServerId).toList();
      if (candidates.isNotEmpty) {
        final newServer = candidates[rng.nextInt(candidates.length)];
        ref.read(vpnStateProvider.notifier).selectServer(newServer.id);
        return;
      }
    }

    await storage.delete(SecureStorage.selectedServerKey);
    ref.read(vpnStateProvider.notifier).selectServer(null);
  }

  void _addStep(String label) {
    if (!mounted) return;
    setState(() {
      _steps.add(_PanicStep(label: label, completed: null));
    });
  }

  void _updateStep(String label, bool success) {
    if (!mounted) return;
    setState(() {
      if (_steps.isNotEmpty) {
        _steps[_steps.length - 1] =
            _PanicStep(label: label, completed: success);
      }
    });
  }

  Color _statusColor(String status) {
    return switch (status) {
      'connected' => AppUIv1.success,
      'connecting' || 'disconnecting' => AppUIv1.warning,
      _ => AppUIv1.inkSoft,
    };
  }

  @override
  Widget build(BuildContext context) {
    final vpnState = ref.watch(vpnStateProvider);
    final status = vpnState.status.name;
    final statusColor = _statusColor(status);

    return Scaffold(
      appBar: AppBar(title: const Text('Panic button')),
      body: SecurePageBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final padding = AppUIv1.pagePaddingFor(constraints.maxWidth);

              return SingleChildScrollView(
                padding: padding,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppUIv1.contentWideMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SecureSurface(
                          variant: SecureSurfaceVariant.danger,
                          padding: const EdgeInsets.all(AppUIv1.space5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppUIv1.danger.withValues(alpha: 0.18),
                                  border: Border.all(
                                    color:
                                        AppUIv1.danger.withValues(alpha: 0.42),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.warning_amber_rounded,
                                  color: AppUIv1.danger,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: AppUIv1.space4),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Emergency actions',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium,
                                    ),
                                    const SizedBox(height: AppUIv1.space1),
                                    Text(
                                      'Disconnect the VPN, clear cached tunnel data, rotate server preference, and sign out.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppUIv1.space4),
                        SecureSurface(
                          variant: SecureSurfaceVariant.glass,
                          padding: const EdgeInsets.all(AppUIv1.space4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.shield_outlined,
                                    color: AppUIv1.accentCyan,
                                  ),
                                  const SizedBox(width: AppUIv1.space2),
                                  Expanded(
                                    child: Text(
                                      'Current VPN status',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  SecureStatePill(
                                    label: status,
                                    color: statusColor,
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppUIv1.space4),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppUIv1.danger,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: _running
                                      ? null
                                      : () {
                                          unawaited(AppHaptics.panicTap());
                                          _runPanic();
                                        },
                                  icon: _running
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.power_settings_new_rounded,
                                        ),
                                  label: Text(
                                    _running
                                        ? 'Working...'
                                        : 'Panic: Emergency disconnect',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_steps.isNotEmpty) ...[
                          const SizedBox(height: AppUIv1.space4),
                          _ProgressPanel(steps: _steps),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: AppUIv1.space4),
                          SecureSurface(
                            variant: SecureSurfaceVariant.danger,
                            padding: const EdgeInsets.all(AppUIv1.space4),
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
                                    _error!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: AppUIv1.danger),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: AppUIv1.space4),
                        if (_done)
                          const _CompletionPanel()
                        else
                          const _PanicGuidePanel(),
                      ],
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

class _PanicStep {
  const _PanicStep({required this.label, required this.completed});

  final String label;
  final bool? completed;
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.steps});

  final List<_PanicStep> steps;

  @override
  Widget build(BuildContext context) {
    return SecureSurface(
      variant: SecureSurfaceVariant.glass,
      padding: const EdgeInsets.all(AppUIv1.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Progress', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space3),
          for (final step in steps) ...[
            _PanicStepRow(step: step),
            if (step != steps.last) const SizedBox(height: AppUIv1.space2),
          ],
        ],
      ),
    );
  }
}

class _PanicStepRow extends StatelessWidget {
  const _PanicStepRow({required this.step});

  final _PanicStep step;

  @override
  Widget build(BuildContext context) {
    final completed = step.completed;
    final icon = completed == null
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(
            completed ? Icons.check_circle : Icons.error,
            size: 18,
            color: completed ? AppUIv1.success : AppUIv1.danger,
          );

    return SecureSurface(
      variant: SecureSurfaceVariant.base,
      padding: const EdgeInsets.all(AppUIv1.space3),
      child: Row(
        children: [
          icon,
          const SizedBox(width: AppUIv1.space2),
          Expanded(
            child:
                Text(step.label, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _CompletionPanel extends StatelessWidget {
  const _CompletionPanel();

  @override
  Widget build(BuildContext context) {
    return SecureSurface(
      variant: SecureSurfaceVariant.glass,
      padding: const EdgeInsets.all(AppUIv1.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: AppUIv1.success),
              const SizedBox(width: AppUIv1.space2),
              Expanded(
                child: Text(
                  'Emergency protocol completed',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppUIv1.space3),
          Text(
            'All automated actions completed. Follow the steps below for a full response:',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppUIv1.space3),
          const _Step(
            'Change your SecureWave password immediately from a trusted device.',
          ),
          const _Step('Enable 2FA in the web portal if available.'),
          const _Step('Revoke unknown devices in the web Device Center.'),
          const _Step(
            'Close any sensitive browser tabs and clear browser cache manually.',
          ),
          const _Step('Update your OS and run a malware scan.'),
          const _Step(
            'If you suspect account takeover, contact support and request a forced key rotation.',
          ),
          const SizedBox(height: AppUIv1.space3),
          Text(
            'Note: This action does not close other apps or clear system browser caches. You must do these manually for full protection.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      ),
    );
  }
}

class _PanicGuidePanel extends StatelessWidget {
  const _PanicGuidePanel();

  @override
  Widget build(BuildContext context) {
    return SecureSurface(
      variant: SecureSurfaceVariant.glass,
      padding: const EdgeInsets.all(AppUIv1.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What this does',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space3),
          const _StepNumbered(1, 'Instantly disconnects the VPN tunnel.'),
          const _StepNumbered(2, 'Clears your cached tunnel profile data.'),
          const _StepNumbered(
            3,
            'Rotates your server preference to a different location.',
          ),
          const _StepNumbered(
            4,
            'Signs you out and clears all authentication tokens.',
          ),
          const SizedBox(height: AppUIv1.space4),
          Text('When to use this',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppUIv1.space3),
          const _Step('You think your account or device may be compromised.'),
          const _Step(
            'You want to immediately stop tunneling and invalidate tokens.',
          ),
          const _Step(
            'You are troubleshooting auth/profile issues and want a clean reset.',
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppUIv1.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.arrow_right, size: 18, color: AppUIv1.inkSoft),
          ),
          const SizedBox(width: AppUIv1.space1),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _StepNumbered extends StatelessWidget {
  const _StepNumbered(this.number, this.text);

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppUIv1.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppUIv1.accent.withValues(alpha: 0.12),
              border: Border.all(
                color: AppUIv1.accent.withValues(alpha: 0.24),
              ),
            ),
            child: Center(
              child: Text(
                '$number',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppUIv1.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppUIv1.space2),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

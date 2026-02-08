import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/auth_session.dart';
import '../../core/services/secure_storage.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
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
      // 1) Disconnect VPN immediately.
      _addStep('Disconnecting VPN tunnel');
      await ref.read(vpnStateProvider.notifier).disconnect();
      _updateStep('VPN disconnected', true);

      // 2) Clear cached profile + tokens.
      _addStep('Clearing cached tunnel profile');
      final storage = SecureStorage();
      await storage.delete(SecureStorage.vpnProfileConfigKey);
      await storage.delete(SecureStorage.vpnProfileExpiresAtKey);
      _updateStep('Tunnel profile cleared', true);

      // 3) Rotate server preference to a different server.
      _addStep('Rotating server preference');
      await _rotateServerPreference();
      _updateStep('Server preference rotated', true);

      // 4) Sign out (clears auth tokens).
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
      // Pick a different server than the current one
      final rng = Random();
      final candidates = serverList.where((s) => s.id != currentServerId).toList();
      if (candidates.isNotEmpty) {
        final newServer = candidates[rng.nextInt(candidates.length)];
        ref.read(vpnStateProvider.notifier).selectServer(newServer.id);
        return;
      }
    }

    // Fallback: clear server preference (will auto-select next time)
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
        _steps[_steps.length - 1] = _PanicStep(label: label, completed: success);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final vpnState = ref.watch(vpnStateProvider);
    final status = vpnState.status.name;

    return Scaffold(
      appBar: AppBar(title: const Text('Panic button')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppUIv1.contentMaxWidth),
            child: ListView(
              padding: const EdgeInsets.all(AppUIv1.space5),
              children: [
                Text('Emergency actions', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppUIv1.space2),
                Text(
                  'This performs a safe, reversible emergency protocol: disconnects the VPN, '
                  'clears session tokens, rotates your server preference, and signs you out.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppUIv1.space4),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppUIv1.space4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.shield_outlined),
                            const SizedBox(width: AppUIv1.space2),
                            Expanded(
                              child: Text(
                                'Current VPN status: $status',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppUIv1.space3),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppUIv1.danger,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _running ? null : _runPanic,
                            icon: _running
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.warning_amber_rounded),
                            label: Text(_running ? 'Working...' : 'Panic: Emergency disconnect'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Progress steps
                if (_steps.isNotEmpty) ...[
                  const SizedBox(height: AppUIv1.space3),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppUIv1.space4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Progress', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: AppUIv1.space2),
                          ..._steps.map((step) => Padding(
                            padding: const EdgeInsets.only(bottom: AppUIv1.space2),
                            child: Row(
                              children: [
                                if (step.completed == null)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                else if (step.completed!)
                                  const Icon(Icons.check_circle, size: 16, color: AppUIv1.success)
                                else
                                  const Icon(Icons.error, size: 16, color: AppUIv1.danger),
                                const SizedBox(width: AppUIv1.space2),
                                Expanded(
                                  child: Text(step.label, style: Theme.of(context).textTheme.bodySmall),
                                ),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: AppUIv1.space3),
                  Text(
                    _error!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppUIv1.danger),
                  ),
                ],
                const SizedBox(height: AppUIv1.space4),
                if (_done) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppUIv1.space5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle, color: AppUIv1.success),
                              const SizedBox(width: AppUIv1.space2),
                              Text('Emergency protocol completed', style: Theme.of(context).textTheme.titleMedium),
                            ],
                          ),
                          const SizedBox(height: AppUIv1.space3),
                          Text(
                            'All automated actions completed. Follow the steps below for a full response:',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: AppUIv1.space2),
                          const _Step('Change your SecureWave password immediately from a trusted device.'),
                          const _Step('Enable 2FA in the web portal if available.'),
                          const _Step('Revoke unknown devices in the web Device Center.'),
                          const _Step('Close any sensitive browser tabs and clear browser cache manually.'),
                          const _Step('Update your OS and run a malware scan.'),
                          const _Step('If you suspect account takeover, contact support and request a forced key rotation.'),
                          const SizedBox(height: AppUIv1.space3),
                          Text(
                            'Note: This action does not close other apps or clear system browser '
                            'caches. You must do these manually for full protection.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppUIv1.space5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('What this does', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: AppUIv1.space2),
                          const _StepNumbered(1, 'Instantly disconnects the VPN tunnel.'),
                          const _StepNumbered(2, 'Clears your cached tunnel profile data.'),
                          const _StepNumbered(3, 'Rotates your server preference to a different location.'),
                          const _StepNumbered(4, 'Signs you out and clears all authentication tokens.'),
                          const SizedBox(height: AppUIv1.space3),
                          Text('When to use this', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: AppUIv1.space2),
                          const _Step('You think your account or device may be compromised.'),
                          const _Step('You want to immediately stop tunneling and invalidate tokens.'),
                          const _Step('You are troubleshooting auth/profile issues and want a clean reset.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
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
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
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
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/auth_session.dart';
import '../../core/services/secure_storage.dart';
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

  Future<void> _runPanic() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
    });

    try {
      // 1) Disconnect if needed.
      await ref.read(vpnStateProvider.notifier).disconnect();

      // 2) Clear cached profile + server preference.
      final storage = SecureStorage();
      await storage.delete(SecureStorage.vpnProfileConfigKey);
      await storage.delete(SecureStorage.vpnProfileExpiresAtKey);
      await storage.delete(SecureStorage.selectedServerKey);

      // 3) Sign out (clears tokens).
      await ref.read(authSessionProvider).clearSession();

      if (!mounted) return;
      setState(() => _done = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
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
                  'This performs a safe, reversible reset: disconnects the VPN, clears your session tokens, and removes cached tunnel profile data.',
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
                            label: Text(_running ? 'Working…' : 'Panic: Disconnect & sign out'),
                          ),
                        ),
                        const SizedBox(height: AppUIv1.space2),
                        Text(
                          'Note: this does not attempt to close other apps or clear browser/system caches. Follow the steps below for a full response.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
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
                              Text('Completed', style: Theme.of(context).textTheme.titleMedium),
                            ],
                          ),
                          const SizedBox(height: AppUIv1.space3),
                          Text(
                            'Next steps (human actions):',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: AppUIv1.space2),
                          const _Step('Change your SecureWave password immediately.'),
                          const _Step('Enable 2FA in the web portal if available.'),
                          const _Step('Revoke unknown devices in the web Device Center.'),
                          const _Step('Update your OS and run a malware scan.'),
                          const _Step('If you suspect account takeover, contact support and request a forced key rotation.'),
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

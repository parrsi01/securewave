part of '../app.dart';

class _ConnectScreen extends ConsumerWidget {
  const _ConnectScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnStateProvider);
    final user = ref.watch(currentUserProvider);
    final plan = ref.watch(userPlanProvider);
    final servers = ref.watch(serversProvider);
    final config = ref.watch(appConfigProvider);
    final vpnService = ref.watch(vpnServiceProvider);
    final runtimeAvailable = vpnService.canConnectProtocol(
      VpnProtocol.wireGuard,
    );

    final serverList = servers.maybeWhen(
      data: (value) => value,
      orElse: () => const <ServerRegion>[],
    );
    final selectedServer = _serverLabel(vpn.selectedServerId, serverList);
    final status = _statusDescriptor(vpn);
    final connected = vpn.status == VpnStatus.connected;
    final busy = vpn.isBusy ||
        vpn.status == VpnStatus.connecting ||
        vpn.status == VpnStatus.disconnecting;

    return ListView(
      children: [
        _PlainPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AccountLine(user: user),
              const SizedBox(height: 18),
              _ConnectionStrip(status: status, protocol: vpn.protocol),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 430;
                  final connectButton = FilledButton.icon(
                    onPressed: busy || (!connected && !runtimeAvailable)
                        ? null
                        : () {
                            final notifier = ref.read(
                              vpnStateProvider.notifier,
                            );
                            connected
                                ? unawaited(notifier.disconnect())
                                : unawaited(notifier.connect());
                          },
                    icon: Icon(
                      connected
                          ? Icons.stop_rounded
                          : Icons.power_settings_new_rounded,
                    ),
                    label: Text(connected ? 'Disconnect' : 'Connect'),
                  );
                  final diagnosticsButton = OutlinedButton.icon(
                    onPressed: () => _showDiagnostics(context),
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: const Text('Diagnostics'),
                  );
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        connectButton,
                        const SizedBox(height: 8),
                        diagnosticsButton,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: connectButton),
                      const SizedBox(width: 10),
                      diagnosticsButton,
                    ],
                  );
                },
              ),
              if (vpn.errorMessage != null) ...[
                const SizedBox(height: 12),
                _InlineMessage(
                  icon: Icons.error_outline_rounded,
                  message: vpn.errorMessage!,
                  tone: _Tone.error,
                  actionLabel: connected ? 'Disconnect' : 'Try again',
                  onAction: busy
                      ? null
                      : () => unawaited(
                            connected
                                ? ref
                                    .read(vpnStateProvider.notifier)
                                    .disconnect()
                                : ref.read(vpnStateProvider.notifier).connect(),
                          ),
                ),
              ],
              if (!runtimeAvailable && !connected) ...[
                const SizedBox(height: 12),
                _InlineMessage(
                  icon: Icons.block_rounded,
                  message: vpnService.protocolUnavailableReason(
                        VpnProtocol.wireGuard,
                      ) ??
                      'WireGuard is unavailable on this Linux runtime.',
                  tone: _Tone.warning,
                ),
              ],
              if (config.useMockApi) ...[
                const SizedBox(height: 12),
                const _InlineMessage(
                  icon: Icons.info_outline_rounded,
                  message:
                      'Demo API mode is enabled. Do not treat a demo connection as a real tunnel.',
                  tone: _Tone.warning,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _ResponsivePair(
          left: _PlainPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Session'),
                const SizedBox(height: 12),
                _InfoRow('Server', selectedServer),
                _InfoRow('Protocol', vpnProtocolLabel(vpn.protocol)),
                _InfoRow(
                  'Traffic',
                  connected ? 'Metered by account usage' : 'Disconnected',
                ),
                const _InfoRow('Bridge rates', 'Not exposed'),
              ],
            ),
          ),
          right: _PlainPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('Data'),
                const SizedBox(height: 12),
                plan.when(
                  data: (value) => _UsageSummary(plan: value),
                  loading: () => const _LoadingLine('Loading usage'),
                  error: (_, __) => _InlineMessage(
                    icon: Icons.warning_amber_rounded,
                    message: 'Usage could not be loaded.',
                    tone: _Tone.warning,
                    actionLabel: 'Retry',
                    onAction: () => ref.invalidate(userPlanProvider),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const _PlainPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionTitle('Protocol'),
              SizedBox(height: 12),
              _WireGuardInfo(),
            ],
          ),
        ),
      ],
    );
  }
}

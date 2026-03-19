import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/models/server_region.dart';
import '../../core/models/vpn_status.dart';
import '../../core/state/app_state.dart';
import '../../core/state/vpn_state.dart';
import '../widgets/vpn_ui_bindings.dart';

class VpnDebugScreen extends ConsumerStatefulWidget {
  const VpnDebugScreen({super.key});

  @override
  ConsumerState<VpnDebugScreen> createState() => _VpnDebugScreenState();
}

class _VpnDebugScreenState extends ConsumerState<VpnDebugScreen> {
  final List<String> _logs = <String>[];

  @override
  Widget build(BuildContext context) {
    ref.listen<VpnState>(vpnStateProvider, (previous, next) {
      if (previous == null) {
        _appendLog('VPN debug screen ready');
        return;
      }
      if (previous.status != next.status) {
        _appendLog(
            'State changed: ${previous.status.name} -> ${next.status.name}');
      }
      if (previous.selectedServerId != next.selectedServerId) {
        _appendLog('Server selected: ${next.selectedServerId ?? 'auto'}');
      }
      if (previous.errorMessage != next.errorMessage &&
          next.errorMessage != null &&
          next.errorMessage!.trim().isNotEmpty) {
        _appendLog('Error: ${next.errorMessage}');
      }
    });

    final vpnState = ref.watch(vpnStateProvider);
    final serversAsync = ref.watch(serversProvider);
    final primaryAction = ref.watch(connectionPrimaryActionProvider);
    final isBusy = ref.watch(connectionBusyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('VPN Debug'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Server',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  serversAsync.when(
                    data: (servers) => _ServerDropdown(
                      servers: servers,
                      selectedServerId: vpnState.selectedServerId,
                      onChanged: (serverId) {
                        ref
                            .read(vpnStateProvider.notifier)
                            .selectServer(serverId);
                        _appendLog('Dropdown changed: ${serverId ?? 'auto'}');
                      },
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (error, _) => Text('Failed to load servers: $error'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Selected server: ${vpnState.selectedServerId ?? 'Auto'}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              child: Row(
                children: [
                  _StatusDot(status: vpnState.status),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Connection state: ${vpnState.status.name}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        primaryAction == ConnectionPrimaryAction.connect &&
                                !isBusy
                            ? connectToVpn
                            : null,
                    child: const Text('Connect'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        primaryAction == ConnectionPrimaryAction.disconnect &&
                                !isBusy
                            ? disconnectFromVpn
                            : null,
                    child: const Text('Disconnect'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Log Output',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 180),
                    child: _logs.isEmpty
                        ? const Align(
                            alignment: Alignment.topLeft,
                            child: Text('No log entries yet.'),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: _logs.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 12),
                            itemBuilder: (context, index) {
                              return Text(
                                _logs[index],
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> connectToVpn() async {
    _appendLog('connectToVpn() called');
    AppLogger.vpn('UI', 'CONNECT_BUTTON_PRESSED', fields: <String, Object?>{
      'server_id': ref.read(vpnStateProvider).selectedServerId ?? 'auto',
      'screen': 'vpn_debug',
    });
    await ref.read(vpnStateProvider.notifier).connect();
  }

  Future<void> disconnectFromVpn() async {
    _appendLog('disconnect requested');
    AppLogger.vpn('UI', 'DISCONNECT_BUTTON_PRESSED',
        fields: const <String, Object?>{'screen': 'vpn_debug'});
    await ref.read(vpnStateProvider.notifier).disconnect();
  }

  void _appendLog(String message) {
    if (!mounted) return;
    final timestamp = DateTime.now().toIso8601String();
    setState(() {
      _logs.insert(0, '[$timestamp] $message');
      if (_logs.length > 40) {
        _logs.removeRange(40, _logs.length);
      }
    });
  }
}

class _ServerDropdown extends StatelessWidget {
  const _ServerDropdown({
    required this.servers,
    required this.selectedServerId,
    required this.onChanged,
  });

  final List<ServerRegion> servers;
  final String? selectedServerId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: _resolveValue(),
      items: <DropdownMenuItem<String?>>[
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Auto'),
        ),
        ...servers.map(
          (server) => DropdownMenuItem<String?>(
            value: server.id,
            child: Text(_labelFor(server)),
          ),
        ),
      ],
      onChanged: onChanged,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  String? _resolveValue() {
    for (final server in servers) {
      if (server.id == selectedServerId) {
        return selectedServerId;
      }
    }
    return null;
  }

  String _labelFor(ServerRegion server) {
    final location = server.country == null
        ? server.name
        : '${server.name} (${server.country})';
    final latency = server.latencyMs == null ? '' : ' • ${server.latencyMs} ms';
    return '$location$latency';
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final VpnStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: _colorFor(status),
        shape: BoxShape.circle,
      ),
    );
  }

  Color _colorFor(VpnStatus status) {
    switch (status) {
      case VpnStatus.connected:
      case VpnStatus.degraded:
        return Colors.green;
      case VpnStatus.connecting:
      case VpnStatus.verifying:
      case VpnStatus.reconnecting:
      case VpnStatus.disconnecting:
        return Colors.orange;
      case VpnStatus.error:
        return Colors.red;
      case VpnStatus.disconnected:
        return Colors.grey;
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

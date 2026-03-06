import 'dart:io';

import 'network_interface_probe.dart';

Future<TunnelInterfaceSnapshot?> probeLinuxTunnelInterfaceImpl() async {
  if (!Platform.isLinux) return null;
  final file = File('/proc/net/dev');
  if (!await file.exists()) return null;
  final lines = await file.readAsLines();
  TunnelInterfaceSnapshot? best;
  for (final line in lines.skip(2)) {
    final parts = line.split(':');
    if (parts.length != 2) continue;
    final interfaceName = parts.first.trim();
    if (!_looksLikeTunnelInterface(interfaceName)) continue;
    final stats = parts.last
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (stats.length < 10) continue;
    final rxBytes = int.tryParse(stats[0]) ?? 0;
    final txBytes = int.tryParse(stats[8]) ?? 0;
    final candidate = TunnelInterfaceSnapshot(
      interfaceName: interfaceName,
      rxBytes: rxBytes,
      txBytes: txBytes,
    );
    if (best == null || (rxBytes + txBytes) > (best.rxBytes + best.txBytes)) {
      best = candidate;
    }
  }
  return best;
}

bool _looksLikeTunnelInterface(String value) {
  final name = value.trim().toLowerCase();
  return name.startsWith('wg') ||
      name.startsWith('sw-wg') ||
      name.startsWith('tun') ||
      name.startsWith('utun') ||
      name.startsWith('ppp') ||
      name.startsWith('ipsec');
}

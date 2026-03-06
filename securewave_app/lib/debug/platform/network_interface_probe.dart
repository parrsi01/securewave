import 'network_interface_probe_stub.dart'
    if (dart.library.io) 'network_interface_probe_io.dart';

class TunnelInterfaceSnapshot {
  const TunnelInterfaceSnapshot({
    required this.interfaceName,
    required this.rxBytes,
    required this.txBytes,
  });

  final String interfaceName;
  final int rxBytes;
  final int txBytes;
}

Future<TunnelInterfaceSnapshot?> probeLinuxTunnelInterface() {
  return probeLinuxTunnelInterfaceImpl();
}

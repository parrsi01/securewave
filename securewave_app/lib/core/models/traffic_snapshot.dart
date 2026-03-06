class TrafficSnapshot {
  const TrafficSnapshot({
    required this.receivedBytes,
    required this.transmittedBytes,
    required this.timestamp,
    this.interfaceName,
    this.countersAvailable = true,
    this.statusMessage,
  });

  final int receivedBytes;
  final int transmittedBytes;
  final DateTime timestamp;
  final String? interfaceName;
  final bool countersAvailable;
  final String? statusMessage;

  static final zero = TrafficSnapshot(
    receivedBytes: 0,
    transmittedBytes: 0,
    timestamp: DateTime.fromMillisecondsSinceEpoch(0),
    countersAvailable: false,
  );
}

class TrafficRate {
  const TrafficRate({
    required this.downloadBytesPerSecond,
    required this.uploadBytesPerSecond,
    required this.sessionDownloadBytes,
    required this.sessionUploadBytes,
  });

  final double downloadBytesPerSecond;
  final double uploadBytesPerSecond;
  final int sessionDownloadBytes;
  final int sessionUploadBytes;

  static const zero = TrafficRate(
    downloadBytesPerSecond: 0,
    uploadBytesPerSecond: 0,
    sessionDownloadBytes: 0,
    sessionUploadBytes: 0,
  );
}

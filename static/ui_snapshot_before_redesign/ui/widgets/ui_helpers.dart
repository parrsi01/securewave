import '../../core/models/server_region.dart';

/// Format a data rate in Mbps to a human-readable string.
///
/// Values >= 1000 Mbps are displayed as Gbps.
/// Examples: "12.3 Mbps", "1.2 Gbps", "0.0 Mbps"
String formatDataRate(double valueMbps) {
  if (valueMbps >= 1000) {
    return '${(valueMbps / 1000).toStringAsFixed(1)} Gbps';
  }
  return '${valueMbps.toStringAsFixed(1)} Mbps';
}

/// Format a byte count to a compact human-readable string.
///
/// Uses binary-adjacent thresholds (1000-based for readability).
/// Examples: "1.2 GB", "450 MB", "12.3 KB", "0 B"
String formatBytesCompact(int bytes) {
  if (bytes < 0) return '0 B';
  if (bytes < 1024) return '$bytes B';

  const units = ['KB', 'MB', 'GB', 'TB'];
  double value = bytes.toDouble();
  int unitIndex = -1;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }

  if (unitIndex < 0) return '$bytes B';
  return '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unitIndex]}';
}

/// Format a [Duration] as a clock display string.
///
/// Always shows hours:minutes:seconds with zero-padding.
/// Example: Duration(hours: 1, minutes: 23, seconds: 45) => "01:23:45"
String formatDurationClock(Duration duration) {
  final totalSeconds = duration.inSeconds.abs();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

/// Convert a two-letter ISO country code to a flag emoji.
///
/// Returns an empty string for null, empty, or invalid codes.
/// Example: "US" => unicode flag, "DE" => unicode flag
String flagEmoji(String? countryCode) {
  if (countryCode == null || countryCode.length != 2) return '';
  final upper = countryCode.toUpperCase();
  // Regional indicator symbols: A = 0x1F1E6
  final first = upper.codeUnitAt(0) - 0x41 + 0x1F1E6;
  final second = upper.codeUnitAt(1) - 0x41 + 0x1F1E6;
  return String.fromCharCodes([first, second]);
}

/// Format a latency value in milliseconds to a display string.
///
/// Returns "--" for null values. Example: 23 => "23 ms"
String latencyLabel(int? latencyMs) {
  if (latencyMs == null) return '--';
  return '$latencyMs ms';
}

/// Estimate a server load percentage (0-100) based on latency heuristic.
///
/// This is a rough UI-only estimate for visual indicators. It uses the
/// server's latency to approximate load — lower latency suggests less load.
///
/// Bands:
///   0-30 ms  => 10-25% (low load)
///   31-80 ms => 25-50% (moderate)
///   81-150 ms => 50-75% (elevated)
///   151+ ms  => 75-95% (high)
///
/// When no latency data is available, returns 50 (unknown/moderate).
int estimateServerLoad(ServerRegion server) {
  final latency = server.latencyMs;
  if (latency == null) return 50;

  if (latency <= 30) {
    // Scale 0-30 ms to 10-25%
    return 10 + ((latency / 30) * 15).round();
  } else if (latency <= 80) {
    // Scale 31-80 ms to 25-50%
    return 25 + (((latency - 30) / 50) * 25).round();
  } else if (latency <= 150) {
    // Scale 81-150 ms to 50-75%
    return 50 + (((latency - 80) / 70) * 25).round();
  } else {
    // Scale 151-300+ ms to 75-95%, clamped
    final scaled = 75 + (((latency - 150) / 150) * 20).round();
    return scaled.clamp(75, 95);
  }
}

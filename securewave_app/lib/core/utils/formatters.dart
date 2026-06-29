String formatMbps(double value) => '${value.toStringAsFixed(1)} Mbps';

String formatMbpsFromBytesPerSecond(double bytesPerSecond) {
  final clamped = bytesPerSecond < 0 ? 0 : bytesPerSecond;
  return formatMbps((clamped * 8) / 1000000);
}

String formatBytes(num bytes) {
  final value = bytes < 0 ? 0 : bytes.toDouble();
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var scaled = value;
  var unitIndex = 0;
  while (scaled >= 1024 && unitIndex < units.length - 1) {
    scaled /= 1024;
    unitIndex += 1;
  }
  if (unitIndex == 0) {
    return '${scaled.round()} ${units[unitIndex]}';
  }
  return '${scaled.toStringAsFixed(1)} ${units[unitIndex]}';
}

String formatByteRate(double bytesPerSecond) {
  return '${formatBytes(bytesPerSecond.round())}/s';
}

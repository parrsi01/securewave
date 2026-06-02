import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/utils/formatters.dart';

void main() {
  test('formatBytes uses binary units and clamps negatives', () {
    expect(formatBytes(-1), '0 B');
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1023), '1023 B');
    expect(formatBytes(1024), '1.0 KB');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(1024 * 1024), '1.0 MB');
    expect(formatBytes(5 * 1024 * 1024 * 1024), '5.0 GB');
  });

  test('formatByteRate renders bytes per second', () {
    expect(formatByteRate(0), '0 B/s');
    expect(formatByteRate(1024), '1.0 KB/s');
    expect(formatByteRate(1536.4), '1.5 KB/s');
  });
}

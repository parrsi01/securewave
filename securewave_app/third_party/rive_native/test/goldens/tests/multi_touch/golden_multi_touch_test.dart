import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import '../../src/rive_golden.dart';

void main() {
  group('Golden - Multi touch tests', () {
    testWidgets('Multi touch updates', (WidgetTester tester) async {
      final golden = RiveGolden(
        name: 'data_binding',
        filePath: 'assets/multitouch.riv',
        widgetTester: tester,
        fit: rive.Fit.contain,
      )
        ..tick()
        // Simple click with single pointer
        ..pointerDown(rive.Vec2D.fromValues(200, 350), pointerId: 1)
        ..tick()
        ..golden()
        ..pointerUp(rive.Vec2D.fromValues(200, 350), pointerId: 1)
        ..tick()
        ..golden()
        // New click gesture started with pointer id 1
        ..pointerDown(rive.Vec2D.fromValues(200, 350), pointerId: 1)
        ..tick()
        ..golden()
        // Pointer up with pointer id 0 should not complete the click gesture
        ..pointerUp(rive.Vec2D.fromValues(200, 350), pointerId: 0)
        ..tick()
        ..golden()

        // Pointer up with pointer id 1 should complete the click gesture
        ..pointerUp(rive.Vec2D.fromValues(200, 350), pointerId: 1)
        ..tick()
        ..golden()

        // Two click gestures interleaved: 1 down - 0 down - 0 up - 1 up
        // should toggle color twice
        ..pointerDown(rive.Vec2D.fromValues(200, 350), pointerId: 1)
        ..tick()
        ..golden()
        ..pointerDown(rive.Vec2D.fromValues(200, 350), pointerId: 0)
        ..tick()
        ..golden()
        ..pointerUp(rive.Vec2D.fromValues(200, 350), pointerId: 0)
        ..tick()
        ..golden()
        ..pointerUp(rive.Vec2D.fromValues(200, 350), pointerId: 1)
        ..tick()
        ..golden()
        ..tick();
      await golden.run();
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart';
import 'package:rive_native/rive_text.dart';

import '../../../src/utils.dart';

void main() {
  group('raw text input tests', () {
    late Font? font;
    setUp(() {
      final bytes = loadFile('assets/fonts/iosevka-rive-light.ttf');
      font = Font.decode(bytes);
      expect(font, isNotNull);
    });

    testWidgets('RawTextInput defaults are as expected',
        (WidgetTester tester) async {
      final input = RawTextInput.make(Factory.flutter);
      expect(input.fontSize, 16);
      input.fontSize = 32;
      expect(input.fontSize, 32);

      expect(input.font, null);

      // Update should be able to be called with a null font and return 0 for no
      // update occurred.
      expect(input.update(), 0);
      input.font = font;
      expect(input.font, font);

      expect(input.maxWidth, 0);
      input.maxWidth = 333;
      expect(input.maxWidth, 333);

      expect(input.maxHeight, 0);
      input.maxHeight = 222;
      expect(input.maxHeight, 222);

      expect(input.paragraphSpacing, 0);
      input.paragraphSpacing = 32;
      expect(input.paragraphSpacing, 32);

      expect(input.sizing, TextSizing.autoWidth);
      input.sizing = TextSizing.autoHeight;
      expect(input.sizing, TextSizing.autoHeight);

      expect(input.overflow, TextOverflow.visible);
      input.overflow = TextOverflow.ellipsis;
      expect(input.overflow, TextOverflow.ellipsis);

      expect(input.selectionCornerRadius, 5);
      input.selectionCornerRadius = 8;
      expect(input.selectionCornerRadius, 8);

      expect(input.separateSelectionText, false);
      input.separateSelectionText = true;
      expect(input.separateSelectionText, true);

      expect(input.text, '');
      expect(input.length, 0);
      input.text = 'hello world';
      expect(input.text, 'hello world');
      expect(input.length, 11);

      expect(AABB.areEqual(input.bounds, AABB()), true);

      expect(input.update(),
          RawTextInput.updatedSelection | RawTextInput.updatedShape);
      expect(AABB.areEqual(input.bounds, AABB.fromLTRB(0.0, 0.0, 176.0, 40.0)),
          true);
    });
  });
}

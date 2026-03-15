import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import '../../src/rive_golden.dart';

/// Data binding images from:
/// - https://picsum.photos/id/237/200/300
/// - https://picsum.photos/id/238/200/300

void main() {
  group('Golden - Data binding tests', () {
    testWidgets('Data binding updates', (WidgetTester tester) async {
      final golden = RiveGolden(
        name: 'data_binding',
        filePath: 'assets/rewards.riv',
        widgetTester: tester,
        fit: rive.Fit.layout,
      )
        ..setLayoutScaleFactor(0.3)
        ..tick()
        ..tick() // TODO: This seems to require two ticks before the layout and layout scale factor is updated
        ..golden()
        ..setStringProperty('Button/State_1', 'Let\'s go this is a test')
        ..setNumberProperty('Coin/Item_Value', 400)
        ..setNumberProperty('Energy_Bar/Lives', 3)
        ..setNumberProperty('Energy_Bar/Energy_Bar', 75)
        ..setColorProperty('Energy_Bar/Bar_Color', Colors.red)
        ..tick()
        ..tick() // TODO: Again it requires two ticks before the layout is properly updated
        ..golden()
        ..setNumberProperty('Coin/Item_Value', 1234)
        ..setNumberProperty('Gem/Item_Value', 4321)
        // Updating the number of coins/gems is a delayed animation, we tick for 1 second
        ..tickFrames(const Duration(seconds: 1))
        ..golden()
        ..triggerProperty('Button/Pressed')
        ..tickFrames(const Duration(milliseconds: 500))
        ..golden()
        ..tickFrames(const Duration(milliseconds: 1000))
        ..golden()
        ..tickFrames(const Duration(milliseconds: 750))
        ..golden()
        ..tick();
      await golden.run();
    });

    testWidgets('Data binding images', (WidgetTester tester) async {
      final (file1, file2) = (
        File('test/assets/images/databound_image_1.jpg'),
        File('test/assets/images/databound_image_2.jpg')
      );
      final (bytes1, bytes2) =
          (file1.readAsBytesSync(), file2.readAsBytesSync());

      // Decode the image bytes to ensure they are valid
      final result = await tester.runAsync(() async {
        return (
          await rive.Factory.flutter.decodeImage(bytes1),
          await rive.Factory.flutter.decodeImage(bytes2)
        );
      });

      final (renderImage1, renderImage2) = result ?? (null, null);

      if (renderImage1 == null || renderImage2 == null) {
        throw Exception('Failed to decode image');
      }

      final golden = RiveGolden(
        name: 'databinding_images',
        filePath: 'assets/databinding_images.riv',
        autoBind: true,
        widgetTester: tester,
      )
        ..tick()
        ..setImageAssetProperty('bound_image', renderImage1)
        ..tick()
        ..golden()
        ..setImageAssetProperty('bound_image', renderImage2)
        ..tick()
        ..golden()
        ..setImageAssetProperty('bound_image', null) // clear the image
        ..tick()
        ..golden()
        ..tick();
      await golden.run();
    });

    testWidgets('Data binding artboards', (WidgetTester tester) async {
      final file = File('test/assets/artboard_db_test.riv');
      final bytes = file.readAsBytesSync();
      final riveFile =
          await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
      final artboardRed = riveFile?.artboardToBind('ArtboardRed');
      final artboardBlue = riveFile?.artboardToBind('ArtboardBlue');
      final artboardGreen = riveFile?.artboardToBind('ArtboardGreen');

      expect(artboardRed, isNotNull);
      expect(artboardBlue, isNotNull);
      expect(artboardGreen, isNotNull);

      final golden = RiveGolden(
        name: 'databinding_artboards',
        filePath: 'assets/artboard_db_test.riv',
        autoBind: true,
        widgetTester: tester,
      )
        ..tick()
        ..golden()
        ..setArtboard('artboard_1', artboardGreen!)
        ..setArtboard('artboard_2', artboardRed!)
        ..tick()
        ..golden()
        ..setArtboard('artboard_1', artboardBlue!)
        ..setArtboard('artboard_2', artboardGreen)
        ..tick()
        ..golden()
        ..tick();
      await golden.run();
    });
  });
}

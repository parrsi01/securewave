// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'golden_comparator.dart';
import '../../src/utils.dart';

typedef WidgetWrapper = Widget Function(Widget child);
typedef CustomActionCallback = void Function(rive.StateMachine stateMachine);

/// A helper class to easily run Rive golden tests.
class RiveGolden {
  final String name;
  final String filePath;
  final String? artboardName;
  final String? stateMachineName;
  final WidgetTester widgetTester;
  final WidgetWrapper? widgetWrapper;
  final bool autoBind;
  final Alignment alignment;
  final rive.Fit fit;

  RiveGolden({
    required this.name,
    required this.filePath,
    required this.widgetTester,
    this.stateMachineName,
    this.artboardName,
    this.widgetWrapper,
    this.autoBind = true,
    this.alignment = Alignment.center,
    this.fit = rive.Fit.contain,
  });

  late rive.File _riveFile;
  late rive.Artboard _artboard;
  late rive.StateMachine _stateMachine;
  late rive.StateMachinePainter _stateMachinePainter;
  rive.ViewModelInstance? _viewModelInstance;
  late Widget widget;

  Future<void> _initialize() async {
    await widgetTester.runAsync(() async {
      final bytes = loadFile(filePath);
      final tmpFile =
          await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
      if (tmpFile == null) {
        throw Exception(
            'Could not decode file to load Rive file from $filePath');
      }
      _riveFile = tmpFile;
    });
    var tmpArtboard = (artboardName == null)
        ? _riveFile.defaultArtboard()
        : _riveFile.artboard(artboardName!);
    if (tmpArtboard == null) {
      throw Exception('Failed to load artboard $artboardName');
    }
    _artboard = tmpArtboard;

    _stateMachinePainter = rive.StateMachinePainter(
        stateMachineName: stateMachineName,
        alignment: alignment,
        fit: fit,
        withStateMachine: (machine) {
          _stateMachine = machine;
          if (!autoBind || _riveFile.viewModelCount == 0) return;
          final vm = _riveFile.defaultArtboardViewModel(_artboard);
          final vmi = vm?.createDefaultInstance();
          if (vmi == null) return;
          _stateMachine.bindViewModelInstance(vmi);
          _viewModelInstance = vmi;
        });

    widget = rive.RiveArtboardWidget(
      artboard: _artboard,
      painter: _stateMachinePainter,
    );
    if (widgetWrapper != null) {
      widget = widgetWrapper!(widget);
    }
    await widgetTester.pumpWidget(widget);
  }

  List<GoldenOption> options = [];
  int goldenCounter = 0;

  /// Adds a [GoldenOption] to the list of options to run.
  void add(GoldenOption option) {
    options.add(option);
  }

  /// Adds a list of [GoldenOption] to the list of options to run.
  void addAll(List<GoldenOption> options) {
    this.options.addAll(options);
  }

  /// Performs a single frame tick (`tester.pump`).
  ///
  /// Optionally pass in `seconds` and `milliseconds` to advance the time by.
  void tick({int? seconds, int? milliseconds}) =>
      add(Tick(seconds: seconds, milliseconds: milliseconds));

  /// Repeatedly pump frames that render the target widget with a fixed time
  /// interval as many as [maxDuration] allows.
  ///
  /// The [maxDuration] argument is required. The interval argument defaults
  /// to 16.683 milliseconds (59.94 FPS).
  void tickFrames(
    Duration maxDuration, [
    Duration interval = const Duration(milliseconds: 16, microseconds: 683),
  ]) =>
      add(TickFrames(maxDuration: maxDuration, interval: interval));

  /// Add a custom action to the state machine
  void customAction(CustomActionCallback callback) =>
      add(CustomAction(callback: callback));

  /// Set a number input on the state machine
  void setNumberInput(String name, double value, {String? path}) =>
      add(SetNumberInput(name: name, value: value, path: path));

  /// Set a boolean input on the state machine
  void setBooleanInput(String name, bool value, {String? path}) =>
      add(SetBooleanInput(name: name, value: value, path: path));

  /// Trigger an input on the state machine
  void triggerInput(String name, {String? path}) =>
      add(TriggerInput(name: name, path: path));

  /// Set an image asset property on the view model instance
  void setImageAssetProperty(String path, rive.RenderImage? value) =>
      add(SetImageAssetProperty(path: path, value: value));

  /// Do a pointer move on the widget
  void pointerMove(rive.Vec2D position, {int pointerId = 0}) =>
      add(PointerMove(position: position, pointerId: pointerId));

  /// Do a pointer up on the widget
  void pointerUp(rive.Vec2D position, {int pointerId = 0}) =>
      add(PointerUp(position: position, pointerId: pointerId));

  /// Do a pointer down on the widget
  void pointerDown(rive.Vec2D position, {int pointerId = 0}) =>
      add(PointerDown(position: position, pointerId: pointerId));

  /// Do a pointer exit on the widget
  void pointerExit(rive.Vec2D position, {int pointerId = 0}) =>
      add(PointerExit(position: position, pointerId: pointerId));

  /// Set a text on the artboard
  void setText(String name, String value, {String? path}) =>
      add(SetText(name: name, value: value, path: path));

  /// Set the layout scale factor of the state machine painter
  void setLayoutScaleFactor(double value) =>
      add(SetLayoutScaleFactor(value: value));

  /// Set a number property on the view model instance
  void setNumberProperty(String path, double value) =>
      add(SetNumberProperty(path: path, value: value));

  /// Set a string property on the view model instance
  void setStringProperty(String path, String value) =>
      add(SetStringProperty(path: path, value: value));

  /// Set a boolean property on the view model instance
  void setBooleanProperty(String path, bool value) =>
      add(SetBooleanProperty(path: path, value: value));

  /// Set a color property on the view model instance
  void setColorProperty(String path, Color value) =>
      add(SetColorProperty(path: path, value: value));

  /// Trigger a trigger on the view model instance
  void triggerProperty(String path) => add(TriggerProperty(path: path));

  /// Set an artboard on the view model instance
  void setArtboard(String path, rive.BindableArtboard value) =>
      add(SetArtboardProperty(path: path, value: value));

  /// Capture a golden image and compare to the existing golden image by `name`.
  ///
  /// Regenerate the goldens by running: `flutter test --update-goldens`
  /// The golden image will be saved as `{name}.png` in the directory where the
  /// test file is located.
  void golden({String? fileName, String reason = ''}) =>
      add(MatchesGolden(fileName: fileName, reason: reason));

  /// Run the golden test with the options added.
  Future<void> run() async {
    await _initialize();

    for (final option in options) {
      switch (option) {
        case Tick():
          if (option.millisecondsToAdvance != 0) {
            await widgetTester
                .pump(Duration(milliseconds: option.millisecondsToAdvance));
          } else {
            await widgetTester.pump();
          }
        case TickFrames():
          await widgetTester.pumpFrames(
              widget, option.maxDuration, option.interval);
        case CustomAction():
          option.callback(_stateMachine);
        case SetNumberInput():
          final number = _stateMachine.number(option.name, path: option.path)!;
          number.value = option.value;
        case SetBooleanInput():
          final boolean =
              _stateMachine.boolean(option.name, path: option.path)!;
          boolean.value = option.value;
        case TriggerInput():
          _stateMachine.trigger(option.name, path: option.path)?.fire();
        case PointerMove():
          _stateMachine.pointerMove(option.position,
              pointerId: option.pointerId);
        case PointerUp():
          _stateMachine.pointerUp(option.position, pointerId: option.pointerId);
        case PointerDown():
          _stateMachine.pointerDown(option.position,
              pointerId: option.pointerId);
        case PointerExit():
          _stateMachine.pointerExit(option.position,
              pointerId: option.pointerId);
        case SetText():
          _artboard.setText(option.name, option.value, path: option.path);
        case SetLayoutScaleFactor():
          _stateMachinePainter.layoutScaleFactor = option.value;
        case SetNumberProperty():
          _viewModelInstance?.number(option.path)!.value = option.value;
        case SetStringProperty():
          _viewModelInstance?.string(option.path)!.value = option.value;
        case SetBooleanProperty():
          _viewModelInstance?.boolean(option.path)!.value = option.value;
        case SetColorProperty():
          _viewModelInstance?.color(option.path)!.value = option.value;
        case TriggerProperty():
          _viewModelInstance?.trigger(option.path)!.trigger();
        case SetImageAssetProperty():
          _viewModelInstance?.image(option.path)!.value = option.value;
        case SetArtboardProperty():
          _viewModelInstance?.artboard(option.path)!.value = option.value;
        case MatchesGolden():
          goldenCounter++;
          String filename;
          if (option.fileName != null) {
            filename = '${option.fileName!}.png';
          } else {
            final goldenCounterString =
                goldenCounter.toString().padLeft(2, '0');
            filename = '${name}_$goldenCounterString.png';
          }
          await expectGoldenMatches(
            find.byType(rive.RiveArtboardWidget),
            filename,
            reason: option.reason,
          );
      }
    }
  }
}

final class _GoldenProceduralPainter extends rive.ProceduralPainter {
  final void Function(rive.Renderer renderer, Size size, double paintPixelRatio)
      paintCall;
  _GoldenProceduralPainter(this.paintCall);

  @override
  bool advance(double elapsedSeconds) => false;

  @override
  void paint(rive.Renderer renderer, Size size, double paintPixelRatio) =>
      paintCall(renderer, size, paintPixelRatio);
}

Future<void> riveProceduralGolden({
  required String name,
  required WidgetTester widgetTester,
  required void Function(
          rive.Renderer renderer, Size size, double paintPixelRatio)
      paint,
  WidgetWrapper? widgetWrapper,
}) async {
  Widget widget = rive.RiveProceduralRenderingWidget(
    riveFactory: rive.Factory.flutter,
    painter: _GoldenProceduralPainter(paint),
  );
  if (widgetWrapper != null) {
    widget = widgetWrapper(widget);
  }
  await widgetTester.pumpWidget(widget);

  String filename = '$name.png';

  await expectGoldenMatches(
    find.byType(rive.RiveProceduralRenderingWidget),
    filename,
  );
}

sealed class GoldenOption {}

class Tick extends GoldenOption {
  int millisecondsToAdvance = 0;

  Tick({int? seconds, int? milliseconds}) {
    if (seconds != null) {
      millisecondsToAdvance += seconds * 1000;
    }

    if (milliseconds != null) {
      millisecondsToAdvance += milliseconds;
    }
  }
}

class TickFrames extends GoldenOption {
  final Duration maxDuration;
  final Duration interval;

  TickFrames({required this.maxDuration, required this.interval});
}

class CustomAction extends GoldenOption {
  final CustomActionCallback callback;

  CustomAction({required this.callback});
}

class SetNumberInput extends GoldenOption {
  final String name;
  final double value;
  final String? path;

  SetNumberInput({required this.name, required this.value, this.path});
}

class SetBooleanInput extends GoldenOption {
  final String name;
  final bool value;
  final String? path;

  SetBooleanInput({required this.name, required this.value, this.path});
}

class TriggerInput extends GoldenOption {
  final String name;
  final String? path;

  TriggerInput({required this.name, this.path});
}

class PointerMove extends GoldenOption {
  final rive.Vec2D position;
  final int pointerId;

  PointerMove({required this.position, required this.pointerId});
}

class PointerUp extends GoldenOption {
  final rive.Vec2D position;
  final int pointerId;

  PointerUp({required this.position, required this.pointerId});
}

class PointerDown extends GoldenOption {
  final rive.Vec2D position;
  final int pointerId;

  PointerDown({required this.position, required this.pointerId});
}

class PointerExit extends GoldenOption {
  final rive.Vec2D position;
  final int pointerId;

  PointerExit({required this.position, required this.pointerId});
}

class SetText extends GoldenOption {
  final String name;
  final String value;
  final String? path;

  SetText({required this.name, required this.value, this.path});
}

class SetLayoutScaleFactor extends GoldenOption {
  final double value;

  SetLayoutScaleFactor({required this.value});
}

class SetNumberProperty extends GoldenOption {
  final String path;
  final double value;

  SetNumberProperty({
    required this.path,
    required this.value,
  });
}

class SetStringProperty extends GoldenOption {
  final String path;
  final String value;

  SetStringProperty({required this.path, required this.value});
}

class SetBooleanProperty extends GoldenOption {
  final String path;
  final bool value;

  SetBooleanProperty({required this.path, required this.value});
}

class SetColorProperty extends GoldenOption {
  final String path;
  final Color value;

  SetColorProperty({required this.path, required this.value});
}

class TriggerProperty extends GoldenOption {
  final String path;

  TriggerProperty({required this.path});
}

class SetImageAssetProperty extends GoldenOption {
  final String path;
  final rive.RenderImage? value;

  SetImageAssetProperty({required this.path, required this.value});
}

class SetArtboardProperty extends GoldenOption {
  final String path;
  final rive.BindableArtboard value;

  SetArtboardProperty({required this.path, required this.value});
}

class MatchesGolden extends GoldenOption {
  final String? fileName;
  final String reason;

  MatchesGolden({this.fileName, this.reason = ''});
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securewave_app/services/external_links.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('securewave/links');
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('opens a valid HTTPS URL through the platform channel', () async {
    final opened = await ExternalLinksService().openUrl(
      'https://securewaveapp.com/contact.html',
    );

    expect(opened, isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'openUrl');
  });

  test('blocks unsafe schemes and credential-bearing URLs locally', () async {
    final service = ExternalLinksService();

    expect(await service.openUrl('file:///etc/passwd'), isFalse);
    expect(
      await service.openUrl('https://user:secret@example.test/'),
      isFalse,
    );
    expect(calls, isEmpty);
  });
}

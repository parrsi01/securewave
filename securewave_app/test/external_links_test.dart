import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securewave_app/services/external_links.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('securewave/links');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'external link service sends valid HTTPS URLs to the native channel',
    () async {
      await ExternalLinksService().openUrl(
        'https://securewaveapp.com/contact.html',
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'openUrl');
      expect(calls.single.arguments, {
        'url': 'https://securewaveapp.com/contact.html',
      });
    },
  );

  test(
    'external link service rejects unsafe URLs before the native channel',
    () async {
      final links = ExternalLinksService();
      await links.openUrl('http://securewaveapp.com/contact.html');
      await links.openUrl('https://user@example.com/contact.html');
      await links.openUrl('not a URL');

      expect(calls, isEmpty);
    },
  );
}

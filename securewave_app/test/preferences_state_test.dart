import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:securewave_app/core/state/preferences_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Stub flutter_secure_storage platform channel (unavailable in test harness)
    final store = <String, String?>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        final args = methodCall.arguments is Map
            ? Map<String, dynamic>.from(methodCall.arguments as Map)
            : const <String, dynamic>{};
        final key = args['key']?.toString();
        switch (methodCall.method) {
          case 'read':
            return key == null ? null : store[key];
          case 'write':
            if (key != null) store[key] = args['value']?.toString();
            return null;
          case 'delete':
            if (key != null) store.remove(key);
            return null;
          case 'deleteAll':
            store.clear();
            return null;
          case 'readAll':
            return Map<String, String>.fromEntries(
              store.entries
                  .where((e) => e.value != null)
                  .map((e) => MapEntry(e.key, e.value!)),
            );
        }
        return null;
      },
    );
  });

  test('Auto-connect preference persists across reload', () async {
    final container1 = ProviderContainer();
    await container1.read(preferencesProvider.notifier).setAutoConnect(false);
    expect(container1.read(preferencesProvider).autoConnect, isFalse);

    container1.dispose();

    final container2 = ProviderContainer();
    addTearDown(container2.dispose);

    final ready = Completer<void>();
    final sub = container2.listen(
      preferencesProvider,
      (_, next) {
        if (next.autoConnect == false && !ready.isCompleted) {
          ready.complete();
        }
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);

    await ready.future.timeout(const Duration(seconds: 2));
    expect(container2.read(preferencesProvider).autoConnect, isFalse);
  });
}

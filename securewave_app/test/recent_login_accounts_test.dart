import 'package:flutter_test/flutter_test.dart';

import 'package:securewave_app/core/services/secure_storage.dart';

import 'state_machine/state_machine_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recent login emails are deduplicated and most-recent-first', () async {
    installSecureStorageMock();
    final storage = SecureStorage();

    await storage.saveRecentLoginEmail('First@Example.com');
    await storage.saveRecentLoginEmail('second@example.com');
    await storage.saveRecentLoginEmail('first@example.com');

    final emails = await storage.getRecentLoginEmails();
    expect(
      emails,
      equals(<String>['first@example.com', 'second@example.com']),
    );
  });

  test('invalid recent-email storage payload is handled safely', () async {
    installSecureStorageMock(initial: <String, String?>{
      SecureStorage.recentLoginEmailsKey: '{not-json}',
    });
    final storage = SecureStorage();
    final emails = await storage.getRecentLoginEmails();
    expect(emails, isEmpty);
  });
}

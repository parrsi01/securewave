import 'package:flutter_test/flutter_test.dart';
import 'package:securewave_app/core/services/adblock_engine.dart';

void main() {
  group('DomainMatcher', () {
    late DomainMatcher matcher;

    setUp(() {
      // Simulate a simple blocklist
      matcher = DomainMatcher({
        'ads.example.com',
        'tracker.net',
        'analytics.com',
        'evil.tracker.net',
      });
    });

    test('blocks exact domain match', () {
      expect(matcher.isBlocked('ads.example.com'), isTrue);
      expect(matcher.isBlocked('tracker.net'), isTrue);
    });

    test('blocks subdomain of blocked domain', () {
      expect(matcher.isBlocked('sub.ads.example.com'), isTrue);
      expect(matcher.isBlocked('deep.sub.ads.example.com'), isTrue);
    });

    test('allows non-blocked domains', () {
      expect(matcher.isBlocked('google.com'), isFalse);
      expect(matcher.isBlocked('safe.example.com'), isFalse);
    });

    test('handles case insensitivity', () {
      expect(matcher.isBlocked('ADS.EXAMPLE.COM'), isTrue);
      expect(matcher.isBlocked('Tracker.Net'), isTrue);
    });

    test('handles whitespace', () {
      expect(matcher.isBlocked('  ads.example.com  '), isTrue);
    });

    test('rejects invalid domains', () {
      expect(matcher.isBlocked(''), isFalse);
      expect(matcher.isBlocked('   '), isFalse);
      expect(matcher.isBlocked('nodot'), isFalse);
    });

    test('blocks more specific subdomain when in list', () {
      // Both tracker.net and evil.tracker.net are blocked
      expect(matcher.isBlocked('tracker.net'), isTrue);
      expect(matcher.isBlocked('evil.tracker.net'), isTrue);
      expect(matcher.isBlocked('other.tracker.net'), isTrue);
    });

    test('returns rule count', () {
      expect(matcher.ruleCount, equals(4));
    });
  });

  group('AdblockEngine parsing', () {
    late AdblockEngine engine;

    setUp(() {
      engine = AdblockEngine(fallbackAssetPath: 'assets/adblock_fallback.txt');
    });

    test('parses EasyList format correctly', () {
      const sampleList = '''
# Comment line
! Another comment
||ads.example.com^
||tracker.net^
||malware.evil.com^

# Empty lines above should be ignored
||analytics.io^
invalid-no-dot
||valid.domain.org^
''';

      final parsed = engine.parseListForTesting(sampleList);

      expect(parsed.contains('ads.example.com'), isTrue);
      expect(parsed.contains('tracker.net'), isTrue);
      expect(parsed.contains('malware.evil.com'), isTrue);
      expect(parsed.contains('analytics.io'), isTrue);
      expect(parsed.contains('valid.domain.org'), isTrue);
      expect(parsed.contains('invalid-no-dot'), isFalse);
      expect(parsed.length, equals(5));
    });

    test('handles various domain formats', () {
      const sampleList = '''
||simple.com^
|| with-spaces.com ^
||double-pipe.com||
subdomain.test.com
''';

      final parsed = engine.parseListForTesting(sampleList);

      expect(parsed.contains('simple.com'), isTrue);
      expect(parsed.contains('with-spaces.com'), isTrue);
      expect(parsed.contains('double-pipe.com'), isTrue);
      expect(parsed.contains('subdomain.test.com'), isTrue);
    });

    test('filters out non-domain entries', () {
      const sampleList = '''
||valid.com^
###element-hiding-rule
*tracking-script.js
||another-valid.org^
''';

      final parsed = engine.parseListForTesting(sampleList);

      expect(parsed.contains('valid.com'), isTrue);
      expect(parsed.contains('another-valid.org'), isTrue);
      // Non-domain entries should be filtered
      expect(parsed.length, equals(2));
    });
  });

  group('DomainMatcher performance', () {
    test('handles large blocklist efficiently', () {
      // Create a large blocklist (10k domains)
      final largeDomains = <String>{};
      for (var i = 0; i < 10000; i++) {
        largeDomains.add('ads$i.example.com');
        largeDomains.add('tracker$i.net');
      }

      final matcher = DomainMatcher(largeDomains);

      // Should complete in reasonable time (<100ms for 1000 lookups)
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        matcher.isBlocked('test$i.example.com');
      }
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: '1000 lookups should complete in <100ms');
    });
  });
}

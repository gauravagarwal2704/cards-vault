import 'package:cards_wallet/services/app_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryDiagnosticLogStore implements DiagnosticLogStore {
  _MemoryDiagnosticLogStore([List<String>? initial])
    : entries = List<String>.from(initial ?? const <String>[]);

  List<String> entries;
  int saveCount = 0;

  @override
  Future<void> clear() async => entries.clear();

  @override
  Future<List<String>> load() async => List<String>.from(entries);

  @override
  Future<void> save(List<String> entries) async {
    saveCount++;
    this.entries = List<String>.from(entries);
  }
}

void main() {
  test(
    'support logs redact card numbers, keys, tokens, queries, and email',
    () {
      const source =
          'PAN 4111 1111 1111 1111 key sk-secret-value '
          'Bearer abc.def token https://example.test?a=private&b=secret '
          'person@example.com expiry 12/30 cvv 123 person@upi';

      final sanitized = AppLogService.sanitize(source);

      expect(sanitized, isNot(contains('4111 1111 1111 1111')));
      expect(sanitized, isNot(contains('sk-secret-value')));
      expect(sanitized, isNot(contains('abc.def')));
      expect(sanitized, isNot(contains('private')));
      expect(sanitized, isNot(contains('person@example.com')));
      expect(sanitized, isNot(contains('12/30')));
      expect(sanitized, isNot(contains('cvv 123')));
      expect(sanitized, isNot(contains('person@upi')));
      expect(sanitized, contains('[REDACTED_CARD_NUMBER]'));
    },
  );

  test('support logs redact internal IDs and filesystem paths', () {
    const source =
        'card 123e4567-e89b-12d3-a456-426614174000 failed at '
        '/Users/private/Documents/card-front.jpg and '
        r'C:\Users\private\card-front.jpg';

    final sanitized = AppLogService.sanitize(source);

    expect(sanitized, isNot(contains('123e4567-e89b-12d3-a456-426614174000')));
    expect(sanitized, isNot(contains('/Users/private')));
    expect(sanitized, isNot(contains(r'C:\Users\private')));
    expect(sanitized, contains('[REDACTED_INTERNAL_ID]'));
    expect(sanitized, contains('[REDACTED_FILE_PATH]'));
  });

  test('action logs are included in the diagnostic report', () {
    AppLogService.instance.action(
      'Card details',
      'Copied protected field',
      details: {'field': 'Card number'},
    );

    final report = AppLogService.instance.buildReport({'platform': 'Android'});

    expect(report, contains('Collected logs'));
    expect(report, contains('[Action/Card details]'));
    expect(report, contains('Copied protected field'));
    expect(report, contains('field=Card number'));
  });

  test(
    'rolling diagnostics restore, expire, and persist a bounded report',
    () async {
      final now = DateTime.now().toUtc();
      final store = _MemoryDiagnosticLogStore([
        '[${now.subtract(const Duration(hours: 80)).toIso8601String()}] '
            '[session=old #1] [Test] expired entry',
        '[${now.subtract(const Duration(hours: 2)).toIso8601String()}] '
            '[session=recent #2] [Test] restored entry',
      ]);
      final service = AppLogService.forTesting(store);

      await service.initializePersistence();
      service.action('Test', 'new entry');
      await service.flush();
      final report = service.buildReport(const <String, String>{});

      expect(report, contains('Retention: 72 hours'));
      expect(report, contains('Maximum retained entries: 2000'));
      expect(report, contains('Maximum retained log data: 1024 KB'));
      expect(report, contains('restored entry'));
      expect(report, contains('new entry'));
      expect(report, isNot(contains('expired entry')));
      expect(store.saveCount, greaterThan(0));
      expect(store.entries.join('\n'), isNot(contains('expired entry')));
    },
  );

  test('timed failures include duration, type, and a redacted stack', () {
    final service = AppLogService.forTesting(_MemoryDiagnosticLogStore());
    final span = service.startSpan('Storage', 'Read attachment');

    span.fail(
      StateError('failed for 123e4567-e89b-12d3-a456-426614174000'),
      StackTrace.fromString('/Users/private/app.dart:10'),
    );
    final report = service.buildReport(const <String, String>{});

    expect(report, contains('Read attachment after'));
    expect(report, contains('errorType=StateError'));
    expect(report, contains('[REDACTED_INTERNAL_ID]'));
    expect(report, contains('[REDACTED_FILE_PATH]'));
  });

  test('rolling diagnostics never exceed the 2000-entry storage cap', () {
    final service = AppLogService.forTesting(_MemoryDiagnosticLogStore());

    for (var index = 0; index < 2105; index++) {
      service.action('Capacity', 'entry', details: {'index': index});
    }
    final report = service.buildReport(const <String, String>{});

    expect(report, contains('Collected logs (2000 entries'));
    expect(report, contains('105 older entries omitted'));
    expect(report, isNot(contains('index=0)')));
    expect(report, contains('index=2104'));
  });

  test(
    'persisted diagnostics stay within the one-megabyte plaintext cap',
    () async {
      final store = _MemoryDiagnosticLogStore();
      final service = AppLogService.forTesting(store);
      await service.initializePersistence();
      final payload = List<String>.filled(3990, 'x').join();

      for (var index = 0; index < 400; index++) {
        service.record('Capacity', '$index $payload');
      }
      await service.flush();

      final retainedBytes = store.entries.fold<int>(
        0,
        (total, entry) => total + entry.length + 3,
      );
      expect(retainedBytes, lessThanOrEqualTo(1024 * 1024));
      expect(store.entries.length, lessThan(400));
    },
  );
}

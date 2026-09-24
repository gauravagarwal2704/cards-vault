import 'dart:io';

import 'package:cards_wallet/utils/debug_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NFC diagnostics are opt-in even in a test debug build', () {
    DebugLogger.setEnabled(false);
    expect(DebugLogger.isEnabled, isFalse);
  });

  test(
    'developer options enable release-safe redacted NFC diagnostics',
    () async {
      SharedPreferences.setMockInitialValues({
        'developer_options_enabled': true,
      });

      await DebugLogger.initialize();

      expect(DebugLogger.isEnabled, isTrue);
      DebugLogger.setEnabled(false);
    },
  );

  test('raw NFC and payment fields are always redacted', () {
    const pan = '4111111111111111';
    const apdu = '00A4040007A000000003101000';
    const response = '70125A0841111111111111115F24032512319000';
    final sanitized = DebugLogger.sanitizeForTesting({
      'command': apdu,
      'response': response,
      'aid': 'A0000000031010',
      'id': '04AABBCCDDEE80',
      'error': 'Failed for card $pan with response $response',
      'pan': pan,
      'track2': '${pan}D25122010000000000000',
      'attempt': 2,
      'maxRetries': 3,
      'length': response.length,
      'hasPAN': true,
      'tags': const ['70', '5A', '5F24'],
    });

    for (final key in const [
      'command',
      'response',
      'aid',
      'id',
      'error',
      'pan',
      'track2',
    ]) {
      expect(sanitized[key], '[REDACTED]', reason: key);
    }
    expect(sanitized['attempt'], 2);
    expect(sanitized['maxRetries'], 3);
    expect(sanitized['hasPAN'], isTrue);
    expect(sanitized.values.join(), isNot(contains(pan)));
    expect(sanitized.values.join(), isNot(contains(apdu)));
    expect(sanitized.values.join(), isNot(contains(response)));
  });

  test('NFC service cannot write payloads directly to console sinks', () {
    final source = File('lib/services/nfc_service.dart').readAsStringSync();

    expect(source, isNot(contains('print(')));
    expect(source, isNot(contains('debugPrint(')));
    expect(source, isNot(contains('developer.log(')));
    expect(source, contains('DebugLogger.log('));
  });
}

import 'dart:io';

import 'package:cards_wallet/services/ai_scan_log_service.dart';
import 'package:cards_wallet/services/ai_scan_settings_service.dart';
import 'package:cards_wallet/services/app_log_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('SmartAI diagnostic retention is opt-in', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await AiScanLogService().isLoggingEnabled(), isFalse);
  });

  test('seeded secrets cannot survive the persisted log allowlist', () {
    const sensitiveValues = [
      '4111111111111111',
      'JOHN PRIVATE DOE',
      '12/30',
      '123',
      'sk-sensitive-key-123456789',
      '/Users/private/card-front.jpg',
      r'C:\Users\private\card-front.jpg',
      'john@upi',
    ];
    final payload = sensitiveValues.join(' | ');
    final entry = AiScanLogEntry(
      id: payload,
      createdAt: DateTime.utc(2026, 8, 26),
      provider: AiScanProvider.openAi,
      model: payload,
      endpoint: 'https://example.test/?secret=$payload',
      httpStatus: 500,
      succeeded: false,
      message: payload,
      requestSummary: payload,
      requestBody: payload,
      responseBody: payload,
      validationSummary: payload,
    );

    final persistedText = entry.toJson().values.join(' | ');
    for (final sensitive in sensitiveValues) {
      expect(persistedText, isNot(contains(sensitive)), reason: sensitive);
    }
    expect(persistedText, contains('HTTP 500'));
    expect(persistedText, contains('openai.com'));
  });

  test(
    'persistent app diagnostics are encrypted, bounded, and time-limited',
    () {
      final source = File('lib/services/app_log_service.dart')
          .readAsStringSync();

      expect(source, contains('AESMode.gcm'));
      expect(source, contains('Duration(hours: 72)'));
      expect(source, contains('_maximumEntries = 2000'));
      expect(source, contains('[REDACTED_INTERNAL_ID]'));
      expect(source, contains('[REDACTED_FILE_PATH]'));
      expect(
        AppLogService.sanitize('/Users/private/card.jpg'),
        isNot(contains('/Users/private')),
      );
    },
  );

  test('card detail errors never interpolate raw exceptions', () {
    final source = File('lib/screens/card_detail_screen.dart')
        .readAsStringSync();

    expect(source, isNot(contains("Text('Failed to delete: \$e')")));
    expect(source, isNot(contains("Text('Failed to share: \$e')")));
    expect(source, isNot(contains('debugPrint(')));
  });
}

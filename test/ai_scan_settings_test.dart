import 'dart:convert';

import 'package:cards_wallet/services/ai_scan_settings_service.dart';
import 'package:cards_wallet/services/ai_card_scan_service.dart';
import 'package:cards_wallet/services/ai_scan_log_service.dart';
import 'package:cards_wallet/services/ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('smart scan requires opt-in, provider consent, and a BYOK key', () {
    expect(
      const AiScanSettings(
        enabled: true,
        provider: AiScanProvider.gemini,
        apiKey: 'user-gemini-key',
        hasProcessingConsent: true,
      ).isConfigured,
      isTrue,
    );
    expect(
      const AiScanSettings(
        enabled: true,
        provider: AiScanProvider.gemini,
        apiKey: 'user-gemini-key',
      ).isConfigured,
      isFalse,
    );
    expect(
      const AiScanSettings(
        enabled: true,
        provider: AiScanProvider.openAi,
      ).isConfigured,
      isFalse,
    );
    expect(
      const AiScanSettings(
        enabled: false,
        provider: AiScanProvider.openAi,
        apiKey: 'user-openai-key',
      ).isConfigured,
      isFalse,
    );
  });

  test('provider disclosure names sent data, retention, and offline path', () {
    expect(AiScanProvider.gemini.processingDisclosure, contains('card images'));
    expect(AiScanProvider.gemini.processingDisclosure, contains('CVV'));
    expect(AiScanProvider.gemini.retentionDisclosure, contains('retention'));
  });

  test('upload client rejects missing consent before reading images', () async {
    final service = AiCardScanService();

    expect(
      () => service.scan(
        imagePaths: const ['/path/that/does/not/exist.jpg'],
        crop: null,
        localResult: const OCRResult(),
        settings: const AiScanSettings(
          enabled: true,
          provider: AiScanProvider.openAi,
          apiKey: 'user-openai-key',
        ),
      ),
      throwsA(
        isA<AiCardScanException>().having(
          (error) => error.message,
          'message',
          contains('processing consent is required'),
        ),
      ),
    );
  });

  test('legacy risk acknowledgement is not promoted to consent', () async {
    SharedPreferences.setMockInitialValues({
      'ai_scan_enabled': true,
      'ai_scan_provider': AiScanProvider.gemini.name,
      'ai_scan_byok_risk_accepted': true,
      'ai_scan_byok_migration_complete': true,
    });

    final settings = await AiScanSettingsService().load(includeApiKey: false);
    final preferences = await SharedPreferences.getInstance();

    expect(settings.enabled, isFalse);
    expect(settings.hasProcessingConsent, isFalse);
    expect(preferences.containsKey('ai_scan_byok_risk_accepted'), isFalse);
  });

  test('processing consent is versioned and scoped to one provider', () async {
    SharedPreferences.setMockInitialValues({
      'ai_scan_byok_migration_complete': true,
      'ai_scan_processing_consent_v1_migration_complete': true,
    });
    final service = AiScanSettingsService();

    await service.acceptProcessingConsent(AiScanProvider.gemini);

    expect(await service.hasProcessingConsent(AiScanProvider.gemini), isTrue);
    expect(await service.hasProcessingConsent(AiScanProvider.openAi), isFalse);
    await service.savePreferences(
      enabled: true,
      provider: AiScanProvider.gemini,
    );
    expect(
      () => service.savePreferences(
        enabled: true,
        provider: AiScanProvider.openAi,
      ),
      throwsStateError,
    );
  });

  test('each provider has a baked-in tested vision model', () {
    expect(AiScanProvider.gemini.apiModelId, 'gemini-3.5-flash-lite');
    expect(AiScanProvider.openAi.apiModelId, 'gpt-5.6-luna');
    expect(AiScanProvider.gemini.modelLabel, isNotEmpty);
    expect(AiScanProvider.openAi.modelLabel, isNotEmpty);
  });

  test('smart scan retries transient failures three times', () {
    const policy = AiScanRetryPolicy();

    expect(policy.maxRetries, 3);
    expect(policy.maxAttempts, 4);
    expect(policy.isRetryableStatus(408), isTrue);
    expect(policy.isRetryableStatus(429), isTrue);
    expect(policy.isRetryableStatus(503), isTrue);
    expect(policy.isRetryableStatus(401), isFalse);
    expect(policy.isRetryableStatus(413), isFalse);
    expect(policy.delayBeforeRetry(2), greaterThan(policy.delayBeforeRetry(1)));
  });

  test('AI errors report the number of exhausted attempts', () {
    const error = AiCardScanException(
      'Could not reach the provider.',
      isRetryable: true,
      attempts: 4,
    );

    expect(error.userMessage, contains('Failed after 4 attempts'));
  });

  test('provider diagnostics omit the complete provider payload', () {
    final safe = AiScanDiagnostics.safeResponseBody(
      '{"authorization":"Bearer secret-token-123",'
      '"openai":"sk-exampleSecret123456789",'
      '"gemini":"AIzaExampleSecret123456789012345"}',
    );

    expect(safe, isNot(contains('secret-token-123')));
    expect(safe, isNot(contains('exampleSecret123456789')));
    expect(safe, AiScanLogEntry.redactedResponseBody);
  });

  test('scan log entries retain only allowlisted metadata', () {
    final createdAt = DateTime.utc(2026, 8, 16, 3, 30);
    final entry = AiScanLogEntry(
      id: 'scan-1',
      createdAt: createdAt,
      provider: AiScanProvider.openAi,
      model: AiScanProvider.openAi.modelLabel,
      endpoint: 'https://api.openai.com/v1/responses',
      httpStatus: 400,
      succeeded: false,
      message: 'Invalid request for /Users/private/card.jpg',
      requestSummary: 'OCR fragment JOHN DOE 4111111111111111',
      requestBody: '{"api_key":"sk-sensitive123456789"}',
      responseBody:
          '{"card_number":"4111111111111111","cardholder_name":"JOHN DOE"}',
      validationSummary: 'Accepted 4111111111111111 for JOHN DOE',
    );

    final restored = AiScanLogEntry.fromJson(entry.toJson());
    expect(restored.provider, AiScanProvider.openAi);
    expect(restored.createdAt, createdAt.toLocal());
    expect(restored.requestBody, AiScanLogEntry.redactedRequestBody);
    expect(restored.responseBody, AiScanLogEntry.redactedResponseBody);
    final persisted = jsonEncode(restored.toJson());
    expect(persisted, isNot(contains('4111111111111111')));
    expect(persisted, isNot(contains('JOHN DOE')));
    expect(persisted, isNot(contains('sk-sensitive')));
    expect(persisted, isNot(contains('/Users/private')));
  });
}

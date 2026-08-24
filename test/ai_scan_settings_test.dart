import 'package:cards_wallet/services/ai_scan_settings_service.dart';
import 'package:cards_wallet/services/ai_card_scan_service.dart';
import 'package:cards_wallet/services/ai_scan_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('smart scan requires opt-in and a runtime BYOK key', () {
    expect(
      const AiScanSettings(
        enabled: true,
        provider: AiScanProvider.gemini,
        apiKey: 'user-gemini-key',
      ).isConfigured,
      isTrue,
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

  test('provider diagnostics redact common API key formats', () {
    final safe = AiScanDiagnostics.safeResponseBody(
      '{"authorization":"Bearer secret-token-123",'
      '"openai":"sk-exampleSecret123456789",'
      '"gemini":"AIzaExampleSecret123456789012345"}',
    );

    expect(safe, isNot(contains('secret-token-123')));
    expect(safe, isNot(contains('exampleSecret123456789')));
    expect(safe, contains('[REDACTED]'));
  });

  test('scan log entries preserve sanitized request and response details', () {
    final createdAt = DateTime.utc(2026, 8, 16, 3, 30);
    final entry = AiScanLogEntry(
      id: 'scan-1',
      createdAt: createdAt,
      provider: AiScanProvider.openAi,
      model: AiScanProvider.openAi.modelLabel,
      endpoint: 'https://api.openai.com/v1/responses',
      httpStatus: 400,
      succeeded: false,
      message: 'Invalid request',
      requestSummary: 'One sanitized image',
      requestBody: '{"image":"[OMITTED]"}',
      responseBody: '{"error":"invalid"}',
    );

    final restored = AiScanLogEntry.fromJson(entry.toJson());
    expect(restored.provider, AiScanProvider.openAi);
    expect(restored.createdAt, createdAt.toLocal());
    expect(restored.requestBody, contains('[OMITTED]'));
    expect(restored.responseBody, contains('invalid'));
  });
}

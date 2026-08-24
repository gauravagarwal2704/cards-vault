import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/card_data.dart';
import '../models/card_scan_capture.dart';
import '../utils/card_network_utils.dart';
import '../utils/image_utils.dart';
import 'ai_scan_log_service.dart';
import 'ai_scan_settings_service.dart';
import 'ocr_service.dart';

class AiCardScanException implements Exception {
  final String message;
  final AiScanDiagnostics? diagnostics;
  final bool isRetryable;
  final int attempts;

  const AiCardScanException(
    this.message, {
    this.diagnostics,
    this.isRetryable = false,
    this.attempts = 1,
  });

  String get userMessage =>
      attempts > 1 ? '$message Failed after $attempts attempts.' : message;

  AiCardScanException withAttempts(int value) => AiCardScanException(
    message,
    diagnostics: diagnostics,
    isRetryable: isRetryable,
    attempts: value,
  );

  @override
  String toString() => message;
}

typedef AiScanAttemptCallback = void Function(int attempt, int maxAttempts);

class AiScanRetryPolicy {
  final int maxRetries;

  const AiScanRetryPolicy({this.maxRetries = 3});

  int get maxAttempts => maxRetries + 1;

  bool isRetryableStatus(int statusCode) =>
      statusCode == 408 ||
      statusCode == 425 ||
      statusCode == 429 ||
      statusCode >= 500;

  Duration delayBeforeRetry(int retryNumber) {
    const delays = [
      Duration(milliseconds: 450),
      Duration(milliseconds: 900),
      Duration(milliseconds: 1600),
    ];
    return delays[(retryNumber - 1).clamp(0, delays.length - 1)];
  }
}

class AiScanDiagnostics {
  final AiScanProvider provider;
  final String endpoint;
  final String sentSummary;
  final String requestBody;
  final int? httpStatus;
  final String responseBody;
  final String? validationSummary;

  const AiScanDiagnostics({
    required this.provider,
    required this.endpoint,
    required this.sentSummary,
    required this.requestBody,
    required this.httpStatus,
    required this.responseBody,
    this.validationSummary,
  });

  AiScanDiagnostics copyWith({String? validationSummary}) {
    return AiScanDiagnostics(
      provider: provider,
      endpoint: endpoint,
      sentSummary: sentSummary,
      requestBody: requestBody,
      httpStatus: httpStatus,
      responseBody: responseBody,
      validationSummary: validationSummary ?? this.validationSummary,
    );
  }

  static String safeResponseBody(String body) {
    var safe = body
        .replaceAll(
          RegExp(r'Bearer\s+[A-Za-z0-9._\-]+', caseSensitive: false),
          'Bearer [REDACTED]',
        )
        .replaceAll(RegExp(r'sk-[A-Za-z0-9_\-]{8,}'), 'sk-[REDACTED]')
        .replaceAll(RegExp(r'AIza[A-Za-z0-9_\-]{16,}'), 'AIza[REDACTED]');
    try {
      safe = const JsonEncoder.withIndent('  ').convert(jsonDecode(safe));
    } catch (_) {
      // Provider errors are not guaranteed to be JSON. Show their text as-is.
    }
    const maximumCharacters = 16000;
    if (safe.length > maximumCharacters) {
      safe = '${safe.substring(0, maximumCharacters)}\n… response truncated';
    }
    return safe.trim().isEmpty ? '(Empty response body)' : safe.trim();
  }
}

class AiCardScanOutcome {
  final OCRResult result;
  final AiScanDiagnostics diagnostics;

  const AiCardScanOutcome({required this.result, required this.diagnostics});
}

class _PreparedAiImage {
  final Uint8List bytes;
  final int width;
  final int height;
  final bool wasCropped;

  const _PreparedAiImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.wasCropped,
  });
}

class _ProviderScanResult {
  final Map<String, dynamic> fields;
  final AiScanDiagnostics diagnostics;

  const _ProviderScanResult({required this.fields, required this.diagnostics});
}

class AiKeyValidationResult {
  final bool isValid;
  final String message;

  const AiKeyValidationResult({required this.isValid, required this.message});
}

/// Direct BYOK provider client.
///
/// The caller supplies a runtime key loaded from platform secure storage. This
/// class never persists, prints, wraps in an exception, or returns that key.
/// Only a cropped, resized and re-encoded image is sent to the selected
/// provider, and provider output is treated as an untrusted candidate.
class AiCardScanService {
  final AiScanLogService _logService = AiScanLogService();
  final AiScanRetryPolicy retryPolicy;

  AiCardScanService({this.retryPolicy = const AiScanRetryPolicy()});

  static const _prompt = '''
Read only the same payment card visible in these one or more nearby frames.
Compare the frames to overcome glare, blur, low contrast, or embossed digits.
Extract the primary card number, expiry date, and cardholder name exactly as printed.
Never infer obscured characters. Never extract, mention, or return a CVV or security code.
Use null for any field that is not clearly visible. Return only the requested schema.
''';

  static const Map<String, dynamic> _schema = {
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      'card_number': {
        'type': ['string', 'null'],
        'description':
            'Visible primary account number with digits only, or null.',
      },
      'expiry_date': {
        'type': ['string', 'null'],
        'description': 'Visible expiry normalized to MM/YY, or null.',
      },
      'cardholder_name': {
        'type': ['string', 'null'],
        'description': 'Visible cardholder name, or null.',
      },
      'confidence': {'type': 'number', 'minimum': 0, 'maximum': 1},
    },
    'required': ['card_number', 'expiry_date', 'cardholder_name', 'confidence'],
  };

  Future<AiKeyValidationResult> validateApiKey({
    required AiScanProvider provider,
    required String apiKey,
  }) async {
    if (apiKey.trim().isEmpty) {
      return const AiKeyValidationResult(
        isValid: false,
        message: 'Enter an API key first.',
      );
    }

    final client = _newHttpClient();
    try {
      final uri = switch (provider) {
        AiScanProvider.gemini => Uri.https(
          'generativelanguage.googleapis.com',
          '/v1beta/models/${AiScanProvider.gemini.apiModelId}',
        ),
        AiScanProvider.openAi => Uri.https(
          'api.openai.com',
          '/v1/models/${AiScanProvider.openAi.apiModelId}',
        ),
      };
      final request = await client.getUrl(uri);
      _hardenRequest(request);
      _applyAuthentication(request, provider, apiKey.trim());
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      await response.drain<void>();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return AiKeyValidationResult(
          isValid: true,
          message:
              '${provider.label} key verified. CardVault will use ${provider.modelLabel}.',
        );
      }
      return AiKeyValidationResult(
        isValid: false,
        message: _statusMessage(provider, response.statusCode),
      );
    } on SocketException {
      return const AiKeyValidationResult(
        isValid: false,
        message: 'Could not reach the provider. Check your connection.',
      );
    } on TimeoutException {
      return const AiKeyValidationResult(
        isValid: false,
        message: 'Provider verification timed out. Try again.',
      );
    } on HandshakeException {
      return const AiKeyValidationResult(
        isValid: false,
        message:
            'A secure connection to the provider could not be established.',
      );
    } catch (_) {
      return const AiKeyValidationResult(
        isValid: false,
        message: 'The API key could not be verified.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<AiCardScanOutcome> scan({
    required List<String> imagePaths,
    required NormalizedCardCrop? crop,
    required OCRResult localResult,
    required AiScanSettings settings,
    AiScanAttemptCallback? onAttempt,
  }) async {
    if (!settings.isConfigured) {
      throw const AiCardScanException(
        'Smart scanning is enabled, but no provider key is configured.',
      );
    }

    if (imagePaths.isEmpty) {
      throw const AiCardScanException('No card image was available to scan.');
    }

    final preparedImages = <_PreparedAiImage>[];
    for (final path in imagePaths.take(3)) {
      preparedImages.add(await _preparePrivateUpload(path, crop: crop));
    }
    final requestDiagnostics = _requestDiagnostics(
      settings.provider,
      preparedImages,
    );
    for (var attempt = 1; attempt <= retryPolicy.maxAttempts; attempt++) {
      onAttempt?.call(attempt, retryPolicy.maxAttempts);
      final client = _newHttpClient();
      try {
        final providerResult = switch (settings.provider) {
          AiScanProvider.gemini => await _scanWithGemini(
            client,
            preparedImages,
            settings.apiKey,
          ),
          AiScanProvider.openAi => await _scanWithOpenAi(
            client,
            preparedImages,
            settings.apiKey,
          ),
        };
        final validated = _validatedResult(providerResult.fields, localResult);
        final diagnostics = providerResult.diagnostics.copyWith(
          validationSummary: validated.validationSummary,
        );
        await _recordLog(
          diagnostics,
          succeeded: true,
          message: attempt == 1
              ? 'Provider response received and parsed.'
              : 'Provider response received and parsed on attempt $attempt.',
        );
        return AiCardScanOutcome(
          result: validated.result,
          diagnostics: diagnostics,
        );
      } catch (rawError) {
        final error = _asScanException(
          rawError,
          provider: settings.provider,
          diagnostics: requestDiagnostics,
        );
        await _recordLog(
          error.diagnostics ?? requestDiagnostics,
          succeeded: false,
          message:
              'Attempt $attempt/${retryPolicy.maxAttempts}: ${error.message}',
        );
        final canRetry = error.isRetryable && attempt < retryPolicy.maxAttempts;
        if (!canRetry) throw error.withAttempts(attempt);
        await Future<void>.delayed(retryPolicy.delayBeforeRetry(attempt));
      } finally {
        client.close(force: true);
      }
    }

    throw const AiCardScanException('The smart scan could not be completed.');
  }

  AiCardScanException _asScanException(
    Object error, {
    required AiScanProvider provider,
    required AiScanDiagnostics diagnostics,
  }) {
    if (error is AiCardScanException) return error;
    if (error is SocketException) {
      return AiCardScanException(
        'Could not reach ${provider.label}. Check your connection.',
        diagnostics: diagnostics,
        isRetryable: true,
      );
    }
    if (error is TimeoutException) {
      return AiCardScanException(
        'The smart scan timed out. Check your connection and try again.',
        diagnostics: diagnostics,
        isRetryable: true,
      );
    }
    if (error is HandshakeException) {
      return AiCardScanException(
        'A secure connection to the AI provider could not be established.',
        diagnostics: diagnostics,
        isRetryable: true,
      );
    }
    if (error is FormatException) {
      return AiCardScanException(
        '${provider.label} returned an invalid result.',
        diagnostics: diagnostics,
      );
    }
    return AiCardScanException(
      'An unexpected smart scan error occurred (${error.runtimeType}).',
      diagnostics: diagnostics,
    );
  }

  HttpClient _newHttpClient() {
    return HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..userAgent = 'CardVault/1.0';
  }

  Future<void> _recordLog(
    AiScanDiagnostics diagnostics, {
    required bool succeeded,
    required String message,
  }) async {
    try {
      final now = DateTime.now();
      await _logService.append(
        AiScanLogEntry(
          id: '${now.microsecondsSinceEpoch}-${diagnostics.provider.name}',
          createdAt: now,
          provider: diagnostics.provider,
          model: diagnostics.provider.modelLabel,
          endpoint: diagnostics.endpoint,
          httpStatus: diagnostics.httpStatus,
          succeeded: succeeded,
          message: message,
          requestSummary: diagnostics.sentSummary,
          requestBody: diagnostics.requestBody,
          responseBody: diagnostics.responseBody,
          validationSummary: diagnostics.validationSummary,
        ),
      );
    } catch (_) {
      // Diagnostics must never make an otherwise valid scan fail.
    }
  }

  Future<_ProviderScanResult> _scanWithGemini(
    HttpClient client,
    List<_PreparedAiImage> images,
    String apiKey,
  ) async {
    final request = await client.postUrl(
      Uri.https('generativelanguage.googleapis.com', '/v1beta/interactions'),
    );
    _hardenRequest(request);
    request.headers.contentType = ContentType.json;
    _applyAuthentication(request, AiScanProvider.gemini, apiKey.trim());
    request.add(
      utf8.encode(
        jsonEncode({
          'model': AiScanProvider.gemini.apiModelId,
          'input': [
            {'type': 'text', 'text': _prompt},
            for (final image in images)
              {
                'type': 'image',
                'data': base64Encode(image.bytes),
                'mime_type': 'image/jpeg',
              },
          ],
          'response_format': {
            'type': 'text',
            'mime_type': 'application/json',
            'schema': _schema,
          },
          'generation_config': {
            'thinking_level': 'minimal',
            'max_output_tokens': 500,
          },
        }),
      ),
    );

    final response = await request.close().timeout(const Duration(seconds: 40));
    final body = await utf8.decoder.bind(response).join();
    final diagnostics = _responseDiagnostics(
      AiScanProvider.gemini,
      images,
      response.statusCode,
      body,
    );
    _throwForStatus(AiScanProvider.gemini, response.statusCode, diagnostics);
    try {
      final fields = _extractStructuredFields(jsonDecode(body));
      if (fields == null) throw const FormatException('Missing Gemini output');
      return _ProviderScanResult(fields: fields, diagnostics: diagnostics);
    } on FormatException {
      throw AiCardScanException(
        'Google Gemini responded, but CardVault could not read its structured result.',
        diagnostics: diagnostics,
      );
    }
  }

  Future<_ProviderScanResult> _scanWithOpenAi(
    HttpClient client,
    List<_PreparedAiImage> images,
    String apiKey,
  ) async {
    final request = await client.postUrl(
      Uri.https('api.openai.com', '/v1/responses'),
    );
    _hardenRequest(request);
    request.headers.contentType = ContentType.json;
    _applyAuthentication(request, AiScanProvider.openAi, apiKey.trim());
    request.add(
      utf8.encode(
        jsonEncode({
          'model': AiScanProvider.openAi.apiModelId,
          'store': false,
          'max_output_tokens': 500,
          'reasoning': {'effort': 'none'},
          'input': [
            {
              'role': 'user',
              'content': [
                {'type': 'input_text', 'text': _prompt},
                for (final image in images)
                  {
                    'type': 'input_image',
                    'image_url':
                        'data:image/jpeg;base64,${base64Encode(image.bytes)}',
                    'detail': 'high',
                  },
              ],
            },
          ],
          'text': {
            'format': {
              'type': 'json_schema',
              'name': 'card_scan',
              'strict': true,
              'schema': _schema,
            },
          },
        }),
      ),
    );

    final response = await request.close().timeout(const Duration(seconds: 40));
    final body = await utf8.decoder.bind(response).join();
    final diagnostics = _responseDiagnostics(
      AiScanProvider.openAi,
      images,
      response.statusCode,
      body,
    );
    _throwForStatus(AiScanProvider.openAi, response.statusCode, diagnostics);
    try {
      final fields = _extractStructuredFields(jsonDecode(body));
      if (fields == null) throw const FormatException('Missing OpenAI output');
      return _ProviderScanResult(fields: fields, diagnostics: diagnostics);
    } on FormatException {
      throw AiCardScanException(
        'OpenAI responded, but CardVault could not read its structured result.',
        diagnostics: diagnostics,
      );
    }
  }

  void _hardenRequest(HttpClientRequest request) {
    // Provider endpoints are fixed HTTPS URLs. Refusing redirects prevents a
    // credential-bearing request from being replayed to another host.
    request.followRedirects = false;
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
  }

  AiScanDiagnostics _requestDiagnostics(
    AiScanProvider provider,
    List<_PreparedAiImage> images,
  ) {
    final endpoint = switch (provider) {
      AiScanProvider.gemini =>
        'https://generativelanguage.googleapis.com/v1beta/interactions',
      AiScanProvider.openAi => 'https://api.openai.com/v1/responses',
    };
    final totalBytes = images.fold<int>(
      0,
      (total, image) => total + image.bytes.length,
    );
    final sizeKb = (totalBytes / 1024).toStringAsFixed(1);
    final dimensions = images
        .map((image) => '${image.width}×${image.height}')
        .join(', ');
    final imageLabel = images.length == 1 ? 'image' : 'frames';
    return AiScanDiagnostics(
      provider: provider,
      endpoint: endpoint,
      sentSummary:
          '• ${images.length} ${images.first.wasCropped ? 'cropped' : 'selected'} JPEG $imageLabel ($dimensions, $sizeKb KB total)\n'
          '• Each image was resized if necessary and re-encoded to remove EXIF, location, device, and timestamp metadata\n'
          '• Instruction to read card number, expiry date, cardholder name, and confidence as structured JSON\n'
          '• Instruction to return null for uncertain fields and never extract CVV\n'
          '• Your saved API key is sent to this provider only as an HTTPS authentication header; it is redacted from this view\n'
          '• No offline OCR text, other saved cards, or unrelated app data is sent',
      requestBody: _diagnosticRequestBody(provider, images),
      httpStatus: null,
      responseBody: '(No HTTP response was received)',
    );
  }

  AiScanDiagnostics _responseDiagnostics(
    AiScanProvider provider,
    List<_PreparedAiImage> images,
    int statusCode,
    String body,
  ) {
    final request = _requestDiagnostics(provider, images);
    return AiScanDiagnostics(
      provider: provider,
      endpoint: request.endpoint,
      sentSummary: request.sentSummary,
      requestBody: request.requestBody,
      httpStatus: statusCode,
      responseBody: AiScanDiagnostics.safeResponseBody(body),
    );
  }

  String _diagnosticRequestBody(
    AiScanProvider provider,
    List<_PreparedAiImage> images,
  ) {
    String imagePlaceholder(_PreparedAiImage image) =>
        '[JPEG IMAGE DATA OMITTED FROM LOG — ${image.bytes.length} bytes]';
    final payload = switch (provider) {
      AiScanProvider.gemini => {
        'model': provider.apiModelId,
        'input': [
          {'type': 'text', 'text': _prompt},
          for (final image in images)
            {
              'type': 'image',
              'data': imagePlaceholder(image),
              'mime_type': 'image/jpeg',
            },
        ],
        'response_format': {
          'type': 'text',
          'mime_type': 'application/json',
          'schema': _schema,
        },
        'generation_config': {
          'thinking_level': 'minimal',
          'max_output_tokens': 500,
        },
      },
      AiScanProvider.openAi => {
        'model': provider.apiModelId,
        'store': false,
        'max_output_tokens': 500,
        'reasoning': {'effort': 'none'},
        'input': [
          {
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': _prompt},
              for (final image in images)
                {
                  'type': 'input_image',
                  'image_url': imagePlaceholder(image),
                  'detail': 'high',
                },
            ],
          },
        ],
        'text': {
          'format': {
            'type': 'json_schema',
            'name': 'card_scan',
            'strict': true,
            'schema': _schema,
          },
        },
      },
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  void _applyAuthentication(
    HttpClientRequest request,
    AiScanProvider provider,
    String apiKey,
  ) {
    switch (provider) {
      case AiScanProvider.gemini:
        request.headers.set('x-goog-api-key', apiKey);
        request.headers.set('x-goog-api-client', 'cardvault-flutter/1.0');
      case AiScanProvider.openAi:
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    }
  }

  void _throwForStatus(
    AiScanProvider provider,
    int statusCode,
    AiScanDiagnostics diagnostics,
  ) {
    if (statusCode >= 200 && statusCode < 300) return;
    throw AiCardScanException(
      _statusMessage(provider, statusCode),
      diagnostics: diagnostics,
      isRetryable: retryPolicy.isRetryableStatus(statusCode),
    );
  }

  String _statusMessage(AiScanProvider provider, int statusCode) {
    return switch (statusCode) {
      401 => 'The saved ${provider.label} API key is invalid or revoked.',
      403 =>
        '${provider.label} rejected this key. Check its API restrictions and account access.',
      404 =>
        '${provider.modelLabel} is not available to this provider account.',
      413 => 'The sanitized card image is too large for the provider.',
      429 =>
        '${provider.label} quota or rate limit was reached. Check the provider account.',
      >= 500 =>
        '${provider.label} is temporarily unavailable. Try again later.',
      _ => '${provider.label} could not process this smart scan.',
    };
  }

  Future<_PreparedAiImage> _preparePrivateUpload(
    String imagePath, {
    NormalizedCardCrop? crop,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) {
      throw const AiCardScanException(
        'The selected image could not be decoded.',
      );
    }
    image = img.bakeOrientation(image);
    if (crop != null) image = ImageUtils.cropToNormalizedCard(image, crop);

    const maximumLongEdge = 1600;
    if (image.width > maximumLongEdge || image.height > maximumLongEdge) {
      image = image.width >= image.height
          ? img.copyResize(image, width: maximumLongEdge)
          : img.copyResize(image, height: maximumLongEdge);
    }

    // Re-encoding strips EXIF, location, device and timestamp metadata.
    return _PreparedAiImage(
      bytes: Uint8List.fromList(img.encodeJpg(image, quality: 90)),
      width: image.width,
      height: image.height,
      wasCropped: crop != null,
    );
  }

  ({OCRResult result, String validationSummary}) _validatedResult(
    Map<String, dynamic> json,
    OCRResult local,
  ) {
    final aiNumber = _digitsOnly(json['card_number']);
    final numberAccepted =
        aiNumber != null && CardData.isValidCardNumber(aiNumber);
    final cardNumber = numberAccepted ? aiNumber : local.cardNumber;

    final aiExpiry = _stringOrNull(json['expiry_date']);
    final expiryAccepted =
        aiExpiry != null && CardData.isValidExpiryDate(aiExpiry);
    final expiry = expiryAccepted ? aiExpiry : local.expiryDate;
    final aiName = _sanitizedName(json['cardholder_name']);
    final name = aiName ?? local.cardholderName;
    final confidence = ((json['confidence'] as num?)?.toDouble() ?? 0.78).clamp(
      0.0,
      0.98,
    );

    final result = OCRResult(
      cardNumber: cardNumber,
      expiryDate: expiry,
      cardholderName: name,
      cardType: cardNumber == null
          ? local.cardType
          : CardNetworkUtils.cardTypeFromNumber(cardNumber),
      cardNumberConfidence: cardNumber == aiNumber
          ? confidence
          : local.cardNumberConfidence,
      expiryDateConfidence: expiry == aiExpiry
          ? confidence * 0.92
          : local.expiryDateConfidence,
      cardholderNameConfidence: name == aiName
          ? confidence * 0.86
          : local.cardholderNameConfidence,
      overallConfidence: confidence,
      supportingFrames: local.supportingFrames,
      reviewWarnings: [
        'AI-assisted result — verify every digit before saving.',
        if (cardNumber == null) 'Card number was not confidently detected.',
        if (expiry == null) 'Expiry date was not detected.',
      ],
    );
    final validationSummary =
        'Card number: ${aiNumber == null
            ? 'not returned'
            : numberAccepted
            ? 'accepted (length and Luhn valid)'
            : 'rejected (invalid length or Luhn check)'}\n'
        'Expiry date: ${aiExpiry == null
            ? 'not returned'
            : expiryAccepted
            ? 'accepted'
            : 'rejected (invalid or expired format)'}\n'
        'Cardholder name: ${aiName == null ? 'not returned or rejected' : 'accepted'}\n'
        'Provider confidence: ${(confidence * 100).round()}%';
    return (result: result, validationSummary: validationSummary);
  }

  Map<String, dynamic>? _extractStructuredFields(Object? value) {
    if (value is Map) {
      final normalized = value.map((key, item) => MapEntry('$key', item));
      if (normalized.containsKey('card_number') ||
          normalized.containsKey('expiry_date') ||
          normalized.containsKey('cardholder_name')) {
        return Map<String, dynamic>.from(normalized);
      }

      for (final key in const ['output_text', 'text']) {
        final text = normalized[key];
        if (text is String) {
          final decoded = _decodeStructuredText(text);
          if (decoded != null) return decoded;
        }
      }
      for (final item in normalized.values) {
        final fields = _extractStructuredFields(item);
        if (fields != null) return fields;
      }
    } else if (value is List) {
      for (final item in value.reversed) {
        final fields = _extractStructuredFields(item);
        if (fields != null) return fields;
      }
    } else if (value is String) {
      return _decodeStructuredText(value);
    }
    return null;
  }

  Map<String, dynamic>? _decodeStructuredText(String text) {
    var candidate = text.trim();
    if (candidate.startsWith('```')) {
      candidate = candidate
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }
    if (!candidate.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(candidate);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _digitsOnly(Object? value) {
    final text = _stringOrNull(value);
    if (text == null) return null;
    final digits = text.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 12 && digits.length <= 19 ? digits : null;
  }

  String? _sanitizedName(Object? value) {
    final text = _stringOrNull(value);
    if (text == null) return null;
    final cleaned = text
        .replaceAll(RegExp(r"[^A-Za-z .\-']"), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.length >= 3 && cleaned.length <= 40 ? cleaned : null;
  }

  String? _stringOrNull(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

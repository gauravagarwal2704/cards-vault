import 'dart:async';

import 'package:flutter/services.dart';

enum CardTextOcrProfile { general, digits, expiry, name }

class CardTextOcrLine {
  final String text;
  final double confidence;
  final double? left;
  final double? top;
  final double? width;
  final double? height;

  const CardTextOcrLine({
    required this.text,
    required this.confidence,
    this.left,
    this.top,
    this.width,
    this.height,
  });
}

class CardTextOcrResult {
  final List<CardTextOcrLine> lines;
  final double confidence;

  const CardTextOcrResult({required this.lines, required this.confidence});

  bool get isEmpty => lines.isEmpty;
}

class CardTextOcrException implements Exception {
  const CardTextOcrException();
}

/// Still-image-only bridge to Apple Vision on iOS and Tesseract on Android.
///
/// Image orientation, cropping and enhancement stay in Dart so both platforms
/// receive the same deterministic JPEG. No camera buffer or live stream is
/// passed through the method channel.
class CardTextOcrService {
  static const _defaultChannel = MethodChannel('cards_wallet/card_text_ocr');

  CardTextOcrService({
    MethodChannel? channel,
    this.requestTimeout = const Duration(seconds: 20),
  }) : _channel = channel ?? _defaultChannel;

  final MethodChannel _channel;
  final Duration requestTimeout;

  Future<CardTextOcrResult> recognizeImage(
    String path, {
    CardTextOcrProfile profile = CardTextOcrProfile.general,
  }) async {
    try {
      final response = await _channel
          .invokeMapMethod<Object?, Object?>('recognizeImage', {
            'path': path,
            'profile': profile.name,
          })
          .timeout(requestTimeout);
      if (response == null) {
        return const CardTextOcrResult(lines: [], confidence: 0);
      }
      return _fromMap(response);
    } on MissingPluginException {
      throw const CardTextOcrException();
    } on PlatformException {
      throw const CardTextOcrException();
    } on TimeoutException {
      throw const CardTextOcrException();
    }
  }

  CardTextOcrResult _fromMap(Map<Object?, Object?> map) {
    final overallConfidence = ((map['confidence'] as num?)?.toDouble() ?? 0)
        .clamp(0.0, 1.0);
    final nativeLines = map['lines'];
    if (nativeLines is List) {
      final lines = nativeLines
          .whereType<Map<Object?, Object?>>()
          .map(
            (line) => CardTextOcrLine(
              text: (line['text'] as String? ?? '').trim(),
              confidence:
                  ((line['confidence'] as num?)?.toDouble() ??
                          overallConfidence)
                      .clamp(0.0, 1.0),
              left: (line['left'] as num?)?.toDouble(),
              top: (line['top'] as num?)?.toDouble(),
              width: (line['width'] as num?)?.toDouble(),
              height: (line['height'] as num?)?.toDouble(),
            ),
          )
          .where((line) => line.text.isNotEmpty)
          .toList(growable: false);
      return CardTextOcrResult(lines: lines, confidence: overallConfidence);
    }

    final text = map['text'] as String? ?? '';
    final rawLines = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final lineHeight = rawLines.isEmpty ? 0.08 : 0.84 / rawLines.length;
    final lines = <CardTextOcrLine>[
      for (var index = 0; index < rawLines.length; index++)
        CardTextOcrLine(
          text: rawLines[index],
          confidence: overallConfidence,
          left: 0.06,
          top: 0.08 + index * lineHeight,
          width: 0.88,
          height: lineHeight.clamp(0.035, 0.12),
        ),
    ];
    return CardTextOcrResult(lines: lines, confidence: overallConfidence);
  }
}

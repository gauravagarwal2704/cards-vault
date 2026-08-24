import 'dart:io';

import 'package:cards_wallet/models/card_scan_capture.dart';
import 'package:cards_wallet/services/card_text_ocr_service.dart';
import 'package:cards_wallet/services/ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class _FallbackOcr extends CardTextOcrService {
  final calls = <String>[];

  @override
  Future<CardTextOcrResult> recognizeImage(
    String path, {
    CardTextOcrProfile profile = CardTextOcrProfile.general,
  }) async {
    calls.add(path);
    if (calls.length != 2) {
      return const CardTextOcrResult(lines: [], confidence: 0);
    }
    return const CardTextOcrResult(
      confidence: 0.9,
      lines: [
        CardTextOcrLine(
          text: '4111 1111 1111 1111',
          confidence: 0.9,
          left: 0.08,
          top: 0.42,
          width: 0.8,
          height: 0.08,
        ),
        CardTextOcrLine(
          text: 'VALID THRU 12/30',
          confidence: 0.9,
          left: 0.58,
          top: 0.62,
          width: 0.3,
          height: 0.06,
        ),
        CardTextOcrLine(
          text: 'TEST USER',
          confidence: 0.9,
          left: 0.08,
          top: 0.76,
          width: 0.4,
          height: 0.07,
        ),
      ],
    );
  }
}

class _SlowOcr extends CardTextOcrService {
  @override
  Future<CardTextOcrResult> recognizeImage(
    String path, {
    CardTextOcrProfile profile = CardTextOcrProfile.general,
  }) async {
    await Future<void>.delayed(const Duration(seconds: 5));
    return const CardTextOcrResult(lines: [], confidence: 0);
  }
}

void main() {
  test('center crop recovers when the preview guide crop misses', () async {
    final directory = await Directory.systemTemp.createTemp('card_crop_test_');
    addTearDown(() => directory.delete(recursive: true));
    final source = img.Image(width: 1600, height: 1200)
      ..clear(img.ColorRgb8(220, 220, 220));
    final path = '${directory.path}/source.jpg';
    await File(path).writeAsBytes(img.encodeJpg(source));
    final nativeOcr = _FallbackOcr();
    final service = OCRService(textOcr: nativeOcr);

    final result = await service.processImage(
      path,
      crop: const NormalizedCardCrop(
        left: 0,
        top: 0,
        width: 0.18,
        height: 0.18,
      ),
      preprocess: false,
    );

    expect(nativeOcr.calls.length, 3);
    expect(result.cardNumber, '4111111111111111');
    expect(result.expiryDate, '12/30');
    expect(result.cardholderName, 'TEST USER');
  });

  test('accepted card text OCR respects its post-PAN time budget', () async {
    final directory = await Directory.systemTemp.createTemp(
      'card_budget_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = img.Image(width: 640, height: 400)
      ..clear(img.ColorRgb8(220, 220, 220));
    final path = '${directory.path}/accepted.png';
    await File(path).writeAsBytes(img.encodePng(source));
    final stopwatch = Stopwatch()..start();

    final result = await OCRService(textOcr: _SlowOcr()).processImage(
      path,
      imageIsCardCrop: true,
      timeBudget: const Duration(milliseconds: 100),
    );

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(result.expiryDate, isNull);
    expect(result.cardholderName, isNull);
  });
}

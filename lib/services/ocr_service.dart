import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import '../models/card_scan_capture.dart';
import '../utils/card_network_utils.dart';
import '../utils/image_utils.dart';
import 'card_field_resolver.dart';

class OCRResult {
  final String? cardNumber;
  final String? expiryDate;
  final String? cardholderName;
  final String? cardType;
  final double cardNumberConfidence;
  final double expiryDateConfidence;
  final double cardholderNameConfidence;
  final double overallConfidence;
  final int supportingFrames;
  final List<String> reviewWarnings;

  const OCRResult({
    this.cardNumber,
    this.expiryDate,
    this.cardholderName,
    this.cardType,
    this.cardNumberConfidence = 0,
    this.expiryDateConfidence = 0,
    this.cardholderNameConfidence = 0,
    this.overallConfidence = 0,
    this.supportingFrames = 0,
    this.reviewWarnings = const [],
  });

  bool get needsReview => reviewWarnings.isNotEmpty || overallConfidence < 0.82;
}

class OCRService {
  final TextRecognizer _textRecognizer = TextRecognizer();
  final CardFieldResolver _resolver = CardFieldResolver();

  Future<OCRResult> processImage(
    String imagePath, {
    bool preprocess = true,
    NormalizedCardCrop? crop,
  }) {
    return processImages([imagePath], preprocess: preprocess, crop: crop);
  }

  /// Resolves card fields from multiple nearby frames entirely on device.
  ///
  /// The recognizer's line geometry, deterministic payment-card rules, and
  /// agreement across frames contribute independently to field confidence.
  Future<OCRResult> processImages(
    List<String> imagePaths, {
    bool preprocess = true,
    NormalizedCardCrop? crop,
  }) async {
    if (imagePaths.isEmpty) return const OCRResult();

    final scratchDirectory = await Directory.systemTemp.createTemp(
      'cardvault_scan_',
    );
    final observations = <CardTextObservation>[];
    final preparedFrames = <_PreparedFrame>[];

    try {
      for (var index = 0; index < imagePaths.length; index++) {
        final prepared = await _prepareFrame(
          sourcePath: imagePaths[index],
          frameIndex: index,
          crop: crop,
          scratchDirectory: scratchDirectory,
        );
        if (prepared == null) continue;
        preparedFrames.add(prepared);

        try {
          final recognized = await _textRecognizer.processImage(
            InputImage.fromFilePath(prepared.path),
          );
          observations.addAll(
            _observationsFromMlKit(
              recognized,
              prepared,
              recognizerConfidence: crop == null ? 0.76 : 0.82,
            ),
          );
        } catch (_) {
          // A later frame or an enhanced-image pass may still succeed.
        }

        if (crop == null) {
          final centered = await _prepareFrame(
            sourcePath: imagePaths[index],
            frameIndex: index,
            crop: null,
            scratchDirectory: scratchDirectory,
            centerCropToCard: true,
          );
          if (centered != null && centered.path != prepared.path) {
            preparedFrames.add(centered);
            try {
              final recognized = await _textRecognizer.processImage(
                InputImage.fromFilePath(centered.path),
              );
              observations.addAll(
                _observationsFromMlKit(
                  recognized,
                  centered,
                  recognizerConfidence: 0.80,
                ),
              );
            } catch (_) {
              // The full gallery image remains available.
            }
          }
        }
      }

      var resolution = _resolver.resolve(observations);

      if (preprocess &&
          preparedFrames.isNotEmpty &&
          (resolution.cardNumber.value == null ||
              resolution.cardNumber.confidence < 0.82)) {
        // Restrict enhanced-image fallback passes to at most two frames.
        // This keeps scans responsive while still allowing frame consensus.
        for (final frame in preparedFrames.take(2)) {
          observations.addAll(
            await _enhancedObservations(frame, scratchDirectory),
          );
        }
        resolution = _resolver.resolve(observations);
      }

      return _toResult(resolution);
    } finally {
      // No generated crop or enhanced OCR image survives the scan attempt.
      try {
        if (await scratchDirectory.exists()) {
          await scratchDirectory.delete(recursive: true);
        }
      } catch (_) {
        // Cleanup is best effort on platforms where a native recognizer may
        // release its file handle a moment after returning.
      }
    }
  }

  Future<_PreparedFrame?> _prepareFrame({
    required String sourcePath,
    required int frameIndex,
    required NormalizedCardCrop? crop,
    required Directory scratchDirectory,
    bool centerCropToCard = false,
  }) async {
    try {
      final bytes = await File(sourcePath).readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) return null;
      image = img.bakeOrientation(image);
      if (crop != null) image = ImageUtils.cropToNormalizedCard(image, crop);
      if (crop == null && centerCropToCard) {
        image = ImageUtils.centerCropToCardAspect(image);
      }

      const maximumLongEdge = 2000;
      if (image.width > maximumLongEdge || image.height > maximumLongEdge) {
        if (image.width >= image.height) {
          image = img.copyResize(image, width: maximumLongEdge);
        } else {
          image = img.copyResize(image, height: maximumLongEdge);
        }
      }

      final variant = centerCropToCard ? 'center' : 'full';
      final output = File(
        '${scratchDirectory.path}/frame_${frameIndex}_$variant.jpg',
      );
      await output.writeAsBytes(img.encodeJpg(image, quality: 94), flush: true);
      return _PreparedFrame(
        path: output.path,
        frameIndex: frameIndex,
        width: image.width,
        height: image.height,
      );
    } catch (_) {
      return null;
    }
  }

  Iterable<CardTextObservation> _observationsFromMlKit(
    RecognizedText recognized,
    _PreparedFrame frame, {
    required double recognizerConfidence,
  }) sync* {
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        if (line.text.trim().isEmpty) continue;
        final bounds = line.boundingBox;
        yield CardTextObservation(
          text: line.text,
          frameIndex: frame.frameIndex,
          recognizerConfidence: recognizerConfidence,
          box: NormalizedTextBox(
            left: (bounds.left / frame.width).clamp(0, 1),
            top: (bounds.top / frame.height).clamp(0, 1),
            width: (bounds.width / frame.width).clamp(0, 1),
            height: (bounds.height / frame.height).clamp(0, 1),
          ),
        );
      }

      // Some card numbers are split into multiple OCR lines. The block-level
      // observation allows the resolver to recover them with slightly lower
      // trust than a coherent single line.
      if (block.lines.length > 1 && block.text.trim().isNotEmpty) {
        final bounds = block.boundingBox;
        yield CardTextObservation(
          text: block.text.replaceAll('\n', ' '),
          frameIndex: frame.frameIndex,
          recognizerConfidence: recognizerConfidence * 0.86,
          box: NormalizedTextBox(
            left: (bounds.left / frame.width).clamp(0, 1),
            top: (bounds.top / frame.height).clamp(0, 1),
            width: (bounds.width / frame.width).clamp(0, 1),
            height: (bounds.height / frame.height).clamp(0, 1),
          ),
        );
      }
    }
  }

  Future<List<CardTextObservation>> _enhancedObservations(
    _PreparedFrame frame,
    Directory scratchDirectory,
  ) async {
    final observations = <CardTextObservation>[];
    try {
      final bytes = await File(frame.path).readAsBytes();
      var source = img.decodeImage(bytes);
      if (source != null) {
        source = ImageUtils.enhanceContrast(source, contrast: 1.65);
        source = ImageUtils.sharpenImage(source, amount: 1.25);
        final enhancedPath =
            '${scratchDirectory.path}/enhanced_${frame.frameIndex}.jpg';
        await File(enhancedPath)
            .writeAsBytes(img.encodeJpg(source, quality: 94), flush: true);
        final recognized = await _textRecognizer.processImage(
          InputImage.fromFilePath(enhancedPath),
        );
        observations.addAll(
          _observationsFromMlKit(
            recognized,
            _PreparedFrame(
              path: enhancedPath,
              frameIndex: frame.frameIndex,
              width: source.width,
              height: source.height,
            ),
            recognizerConfidence: 0.74,
          ),
        );
      }
    } catch (_) {
      // Original-frame observations remain available if enhancement or the
      // additional recognition pass is unavailable on this device.
    }
    return observations;
  }

  OCRResult _toResult(CardFieldResolution resolution) {
    final warnings = <String>[];
    if (resolution.cardNumber.value == null) {
      warnings.add('Card number was not confidently detected.');
    } else if (resolution.cardNumber.confidence < 0.86) {
      warnings.add('Check every digit of the card number.');
    }
    if (resolution.expiryDate.value == null) {
      warnings.add('Expiry date was not detected.');
    } else if (resolution.expiryDate.confidence < 0.8) {
      warnings.add('Confirm the expiry date.');
    }
    if (resolution.cardholderName.value == null) {
      warnings.add('Cardholder name was not detected.');
    } else if (resolution.cardholderName.confidence < 0.76) {
      warnings.add('Confirm the cardholder name.');
    }

    final cardNumber = resolution.cardNumber.value;
    final overall =
        resolution.cardNumber.confidence * 0.7 +
        resolution.expiryDate.confidence * 0.2 +
        resolution.cardholderName.confidence * 0.1;

    return OCRResult(
      cardNumber: cardNumber,
      expiryDate: resolution.expiryDate.value,
      cardholderName: resolution.cardholderName.value,
      cardType: cardNumber == null
          ? null
          : CardNetworkUtils.cardTypeFromNumber(cardNumber),
      cardNumberConfidence: resolution.cardNumber.confidence,
      expiryDateConfidence: resolution.expiryDate.confidence,
      cardholderNameConfidence: resolution.cardholderName.confidence,
      overallConfidence: overall.clamp(0, 0.99),
      supportingFrames: resolution.cardNumber.supportingFrames,
      reviewWarnings: warnings,
    );
  }

  void dispose() {
    _textRecognizer.close();
  }
}

class _PreparedFrame {
  final String path;
  final int frameIndex;
  final int width;
  final int height;

  const _PreparedFrame({
    required this.path,
    required this.frameIndex,
    required this.width,
    required this.height,
  });
}

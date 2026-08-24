import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

import '../models/card_scan_capture.dart';
import '../utils/card_network_utils.dart';
import '../utils/image_utils.dart';
import 'card_field_resolver.dart';
import 'card_text_ocr_service.dart';

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
  OCRService({CardTextOcrService? textOcr})
    : _textOcr = textOcr ?? CardTextOcrService();

  final CardFieldResolver _resolver = CardFieldResolver();
  final CardTextOcrService _textOcr;

  Future<OCRResult> processImage(
    String imagePath, {
    bool preprocess = true,
    NormalizedCardCrop? crop,
    bool imageIsCardCrop = false,
    Duration? timeBudget,
  }) {
    return processImages(
      [imagePath],
      preprocess: preprocess,
      crop: crop,
      imageIsCardCrop: imageIsCardCrop,
      timeBudget: timeBudget,
    );
  }

  /// Resolves card fields from multiple nearby frames entirely on device.
  ///
  /// The recognizer's line geometry, deterministic payment-card rules, and
  /// agreement across frames contribute independently to field confidence.
  Future<OCRResult> processImages(
    List<String> imagePaths, {
    bool preprocess = true,
    NormalizedCardCrop? crop,
    bool imageIsCardCrop = false,
    Duration? timeBudget,
  }) async {
    if (imagePaths.isEmpty) return const OCRResult();

    final scratchDirectory = await Directory.systemTemp.createTemp(
      'cardvault_scan_',
    );
    final observations = <CardTextObservation>[];
    final preparedFrames = <_PreparedFrame>[];
    final deadline = timeBudget == null ? null : DateTime.now().add(timeBudget);
    var recognitionTimedOut = false;
    // A single clear, Luhn-valid PAN must remain usable. Multiple physical
    // frames still raise confidence and conflicting candidates are rejected,
    // but one missed frame no longer discards an otherwise valid scan.
    const minimumPanSupportingFrames = 1;

    CardFieldResolution resolveObservations() => _resolver.resolve(
      observations,
      minimumPanSupportingFrames: minimumPanSupportingFrames,
    );

    try {
      final recognitionPaths = imagePaths.take(2).toList(growable: false);
      for (var index = 0; index < recognitionPaths.length; index++) {
        final prepared = await _prepareFrame(
          sourcePath: recognitionPaths[index],
          frameIndex: index,
          crop: crop,
          scratchDirectory: scratchDirectory,
          assumeCardCrop: imageIsCardCrop,
        );
        if (prepared == null) continue;
        preparedFrames.add(prepared);

        if (!imageIsCardCrop) {
          final initialObservations = await _recognizeFrame(
            prepared,
            recognizerConfidence: crop == null && !imageIsCardCrop
                ? 0.76
                : 0.84,
            deadline: deadline,
          );
          observations.addAll(initialObservations);
          recognitionTimedOut = deadline != null && !_hasTime(deadline);
          if (recognitionTimedOut) break;
        }

        if (crop == null && !imageIsCardCrop) {
          // Gallery photos do not have a camera-guide crop. Keep the full
          // photo, then try both physical card orientations so a portrait card
          // is not accidentally reduced to a landscape strip.
          for (final portraitCard in [false, true]) {
            final centered = await _prepareFrame(
              sourcePath: recognitionPaths[index],
              frameIndex: index,
              crop: null,
              scratchDirectory: scratchDirectory,
              centerCropToCard: true,
              portraitCard: portraitCard,
            );
            if (centered != null && centered.path != prepared.path) {
              preparedFrames.add(centered);
              observations.addAll(
                await _recognizeFrame(
                  centered,
                  recognizerConfidence: 0.80,
                  deadline: deadline,
                ),
              );
              if (deadline != null && !_hasTime(deadline)) break;
            }
          }
        }
      }

      var resolution = resolveObservations();

      if (!recognitionTimedOut &&
          crop != null &&
          _needsRecognitionFallback(resolution)) {
        // Preview and still-photo aspect ratios vary by camera implementation.
        // If the guide crop misses, try a centered card-aspect crop and then
        // the full oriented photo; a bad preview mapping can no longer hide the
        // card from OCR.
        for (var index = 0; index < min(1, recognitionPaths.length); index++) {
          final centeredFrame = await _prepareFrame(
            sourcePath: recognitionPaths[index],
            frameIndex: index,
            crop: null,
            scratchDirectory: scratchDirectory,
            centerCropToCard: true,
          );
          if (centeredFrame != null) {
            preparedFrames.add(centeredFrame);
            observations.addAll(
              await _recognizeFrame(
                centeredFrame,
                recognizerConfidence: 0.80,
                deadline: deadline,
              ),
            );
          }
          final fullFrame = await _prepareFrame(
            sourcePath: recognitionPaths[index],
            frameIndex: index,
            crop: null,
            scratchDirectory: scratchDirectory,
          );
          if (fullFrame == null) continue;
          preparedFrames.add(fullFrame);
          observations.addAll(
            await _recognizeFrame(
              fullFrame,
              recognizerConfidence: 0.70,
              deadline: deadline,
            ),
          );
        }
        resolution = resolveObservations();
      }

      if (preprocess &&
          !recognitionTimedOut &&
          preparedFrames.isNotEmpty &&
          _needsRecognitionFallback(resolution)) {
        // Enhance the strongest guide/center candidate only. Tesseract is a
        // still-image engine, so bounding the number of passes keeps the scan
        // responsive and avoids native memory spikes.
        final enhancementInputs = preparedFrames.take(1).toList();
        for (final frame in enhancementInputs) {
          observations.addAll(
            await _enhancedObservations(
              frame,
              scratchDirectory,
              preparedFrames: preparedFrames,
              deadline: deadline,
              detailsFirst: imageIsCardCrop,
            ),
          );
        }
        resolution = resolveObservations();
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

  bool _needsRecognitionFallback(CardFieldResolution resolution) {
    return resolution.cardNumber.value == null ||
        resolution.cardNumber.confidence < 0.82 ||
        resolution.expiryDate.value == null ||
        resolution.expiryDate.confidence < 0.78 ||
        resolution.cardholderName.value == null ||
        resolution.cardholderName.confidence < 0.74;
  }

  Future<_PreparedFrame?> _prepareFrame({
    required String sourcePath,
    required int frameIndex,
    required NormalizedCardCrop? crop,
    required Directory scratchDirectory,
    bool centerCropToCard = false,
    bool portraitCard = false,
    bool assumeCardCrop = false,
  }) async {
    try {
      final bytes = await File(sourcePath).readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) return null;
      image = img.bakeOrientation(image);
      if (crop != null) {
        image = ImageUtils.cropToNormalizedCard(image, crop, padding: 0.07);
      }
      if (crop == null && centerCropToCard) {
        image = ImageUtils.centerCropToCardAspect(
          image,
          portrait: portraitCard,
        );
      }

      const maximumLongEdge = 2400;
      final minimumCardShortEdge = assumeCardCrop ? 600 : 900;
      final longEdge = max(image.width, image.height);
      final shortEdge = min(image.width, image.height);
      var scale = longEdge > maximumLongEdge ? maximumLongEdge / longEdge : 1.0;
      if ((crop != null || centerCropToCard || assumeCardCrop) &&
          shortEdge < minimumCardShortEdge) {
        scale = min(
          maximumLongEdge / longEdge,
          minimumCardShortEdge / shortEdge,
        );
      }
      if ((scale - 1).abs() > 0.01) {
        image = img.copyResize(
          image,
          width: (image.width * scale).round(),
          height: (image.height * scale).round(),
          interpolation: img.Interpolation.cubic,
        );
      }

      final variant = assumeCardCrop
          ? 'card_crop'
          : centerCropToCard
          ? portraitCard
                ? 'center_portrait'
                : 'center_landscape'
          : crop != null
          ? 'crop'
          : 'full';
      final output = File(
        '${scratchDirectory.path}/frame_${frameIndex}_$variant.jpg',
      );
      await output.writeAsBytes(img.encodeJpg(image, quality: 94), flush: true);
      return _PreparedFrame(
        path: output.path,
        frameIndex: frameIndex,
        sourceId: 'frame_${frameIndex}_$variant',
        label: switch (variant) {
          'crop' => 'Frame ${frameIndex + 1} · card crop',
          'card_crop' => 'Frame ${frameIndex + 1} · accepted card crop',
          'center_portrait' =>
            'Frame ${frameIndex + 1} · centered portrait crop',
          'center_landscape' =>
            'Frame ${frameIndex + 1} · centered landscape crop',
          _ => 'Frame ${frameIndex + 1} · full image',
        },
        width: image.width,
        height: image.height,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<CardTextObservation>> _recognizeFrame(
    _PreparedFrame frame, {
    required double recognizerConfidence,
    CardTextOcrProfile profile = CardTextOcrProfile.general,
    DateTime? deadline,
  }) async {
    try {
      final remaining = deadline?.difference(DateTime.now());
      if (remaining != null && remaining <= Duration.zero) return const [];
      final request = _textOcr.recognizeImage(frame.path, profile: profile);
      final recognized = remaining == null
          ? await request
          : await request.timeout(remaining);
      return _observationsFromNativeText(
        recognized,
        frame,
        recognizerConfidence: recognizerConfidence,
      ).toList(growable: false);
    } on CardTextOcrException catch (_) {
      return const [];
    } on TimeoutException catch (_) {
      return const [];
    }
  }

  bool _hasTime(DateTime deadline) => DateTime.now().isBefore(deadline);

  Iterable<CardTextObservation> _observationsFromNativeText(
    CardTextOcrResult recognized,
    _PreparedFrame frame, {
    required double recognizerConfidence,
  }) sync* {
    for (final line in recognized.lines) {
      final lineConfidence = line.confidence <= 0
          ? recognizerConfidence * 0.78
          : min(recognizerConfidence, max(0.58, line.confidence));
      final hasGeometry =
          line.left != null &&
          line.top != null &&
          line.width != null &&
          line.height != null;
      yield CardTextObservation(
        text: line.text,
        frameIndex: frame.frameIndex,
        sourceId: frame.sourceId,
        recognizerConfidence: lineConfidence,
        box: hasGeometry
            ? NormalizedTextBox(
                left: line.left!.clamp(0, 1),
                top: line.top!.clamp(0, 1),
                width: line.width!.clamp(0, 1),
                height: line.height!.clamp(0, 1),
              )
            : null,
      );
    }
  }

  Future<List<CardTextObservation>> _enhancedObservations(
    _PreparedFrame frame,
    Directory scratchDirectory, {
    required List<_PreparedFrame> preparedFrames,
    DateTime? deadline,
    bool detailsFirst = false,
  }) async {
    final observations = <CardTextObservation>[];
    try {
      if (deadline != null && !_hasTime(deadline)) return observations;
      final bytes = await File(frame.path).readAsBytes();
      var source = img.decodeImage(bytes);
      if (source != null) {
        if (detailsFirst) {
          final variants = [
            (
              name: 'details_region',
              top: 0.22,
              bottom: 1.0,
              contrast: 1.45,
              confidence: 0.84,
              profile: CardTextOcrProfile.general,
            ),
            (
              name: 'expiry_region',
              top: 0.30,
              bottom: 0.90,
              contrast: 1.65,
              confidence: 0.84,
              profile: CardTextOcrProfile.expiry,
            ),
            (
              name: 'name_region',
              top: 0.48,
              bottom: 1.0,
              contrast: 1.35,
              confidence: 0.82,
              profile: CardTextOcrProfile.name,
            ),
          ];
          final sourceName = frame.path
              .split(Platform.pathSeparator)
              .last
              .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
          for (final variant in variants) {
            if (deadline != null && !_hasTime(deadline)) break;
            final region = _cropVerticalBand(
              source,
              variant.top,
              variant.bottom,
            );
            final enhancedRegion = ImageUtils.enhanceContrast(
              img.grayscale(region),
              contrast: variant.contrast,
            );
            if (deadline != null && !_hasTime(deadline)) break;
            final variantPath =
                '${scratchDirectory.path}/${variant.name}_$sourceName.jpg';
            await File(variantPath).writeAsBytes(
              img.encodeJpg(enhancedRegion, quality: 94),
              flush: true,
            );
            final preparedVariant = _PreparedFrame(
              path: variantPath,
              frameIndex: frame.frameIndex,
              sourceId: '${frame.sourceId}_${variant.name}',
              label: '${frame.label} · details-focused region',
              width: enhancedRegion.width,
              height: enhancedRegion.height,
            );
            preparedFrames.add(preparedVariant);
            observations.addAll(
              await _recognizeFrame(
                preparedVariant,
                recognizerConfidence: variant.confidence,
                profile: variant.profile,
                deadline: deadline,
              ),
            );
          }
          return observations;
        }

        final detailsRegion = _cropVerticalBand(source, 0.22, 1.0);
        final expiryRegion = _cropVerticalBand(source, 0.30, 0.90);
        final nameRegion = _cropVerticalBand(source, 0.48, 1.0);
        final grayscale = img.grayscale(source);
        final enhanced = ImageUtils.sharpenImage(
          ImageUtils.enhanceContrast(grayscale, contrast: 1.55),
          amount: 1.25,
        );
        final threshold = img.luminanceThreshold(
          img.Image.from(enhanced),
          threshold: 0.53,
        );
        final enhancedExpiry = _enhanceTextRegion(
          expiryRegion,
          contrast: 1.75,
          sharpen: 1.2,
        );
        final enhancedName = _enhanceTextRegion(
          nameRegion,
          contrast: 1.45,
          sharpen: 1.05,
        );
        final enhancedDetails = _enhanceTextRegion(
          detailsRegion,
          contrast: 1.55,
          sharpen: 1.1,
        );
        final sourceName = frame.path
            .split(Platform.pathSeparator)
            .last
            .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
        final standardVariants = [
          (
            name: 'enhanced',
            image: enhanced,
            confidence: 0.76,
            profile: CardTextOcrProfile.general,
          ),
          (
            name: 'digits',
            image: threshold,
            confidence: 0.80,
            profile: CardTextOcrProfile.digits,
          ),
        ];
        final detailVariants = [
          (
            name: 'details_region',
            image: enhancedDetails,
            confidence: 0.84,
            profile: CardTextOcrProfile.general,
          ),
          (
            name: 'expiry_region',
            image: enhancedExpiry,
            confidence: 0.84,
            profile: CardTextOcrProfile.expiry,
          ),
          (
            name: 'name_region',
            image: enhancedName,
            confidence: 0.82,
            profile: CardTextOcrProfile.name,
          ),
        ];
        final variants = [...standardVariants, ...detailVariants];

        for (final variant in variants) {
          if (deadline != null && !_hasTime(deadline)) break;
          final variantPath =
              '${scratchDirectory.path}/${variant.name}_$sourceName.jpg';
          await File(variantPath).writeAsBytes(
            img.encodeJpg(variant.image, quality: 94),
            flush: true,
          );
          final preparedVariant = _PreparedFrame(
            path: variantPath,
            frameIndex: frame.frameIndex,
            sourceId: '${frame.sourceId}_${variant.name}',
            label:
                '${frame.label} · ${switch (variant.name) {
                  'enhanced' => 'grayscale enhanced',
                  'digits' => 'numeric threshold',
                  'details_region' => 'details-focused region',
                  'expiry_region' => 'expiry-focused region',
                  _ => 'name-focused region',
                }}',
            width: variant.image.width,
            height: variant.image.height,
          );
          preparedFrames.add(preparedVariant);
          observations.addAll(
            await _recognizeFrame(
              preparedVariant,
              recognizerConfidence: variant.confidence,
              profile: variant.profile,
              deadline: deadline,
            ),
          );
        }
      }
    } catch (_) {
      // Original and alternate crop observations remain available.
    }
    return observations;
  }

  img.Image _cropVerticalBand(img.Image source, double top, double bottom) {
    final y = (source.height * top).round().clamp(0, source.height - 1);
    final height = (source.height * (bottom - top)).round().clamp(
      1,
      source.height - y,
    );
    return img.copyCrop(
      source,
      x: 0,
      y: y,
      width: source.width,
      height: height,
    );
  }

  img.Image _enhanceTextRegion(
    img.Image source, {
    required double contrast,
    required double sharpen,
  }) {
    var result = ImageUtils.sharpenImage(
      ImageUtils.enhanceContrast(img.grayscale(source), contrast: contrast),
      amount: sharpen,
    );
    final scale = min(1.6, 2400 / result.width);
    if (scale > 1.05) {
      result = img.copyResize(
        result,
        width: (result.width * scale).round(),
        height: (result.height * scale).round(),
        interpolation: img.Interpolation.cubic,
      );
    }
    return result;
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

  void dispose() {}
}

class _PreparedFrame {
  final String path;
  final int frameIndex;
  final String sourceId;
  final String label;
  final int width;
  final int height;

  const _PreparedFrame({
    required this.path,
    required this.frameIndex,
    required this.sourceId,
    required this.label,
    required this.width,
    required this.height,
  });
}

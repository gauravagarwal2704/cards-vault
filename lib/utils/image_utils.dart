import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

import '../models/card_scan_capture.dart';

class ImageQuality {
  final double blurScore;
  final double brightness;
  final double contrast;
  final double glareRatio;
  final bool isGoodQuality;
  final String? warning;

  ImageQuality({
    required this.blurScore,
    required this.brightness,
    this.contrast = 0,
    this.glareRatio = 0,
    required this.isGoodQuality,
    this.warning,
  });
}

class ImageUtils {
  static const double minBlurScore = 100.0;
  static const double minBrightness = 40.0;
  static const double maxBrightness = 220.0;
  static const double minContrast = 24.0;
  static const double maxGlareRatio = 0.18;
  // These limits apply to the card crop, not the full camera frame. A card
  // occupying the on-screen guide is commonly 300-600 px across even when the
  // source photo is high resolution, and that is still ample for OCR after the
  // recognition resize pass.
  static const int minCardShortEdge = 280;
  static const int minCardLongEdge = 440;

  static img.Image cropToNormalizedCard(
    img.Image image,
    NormalizedCardCrop crop, {
    double padding = 0.025,
  }) {
    final left = (crop.left - padding).clamp(0.0, 1.0);
    final top = (crop.top - padding).clamp(0.0, 1.0);
    final right = (crop.left + crop.width + padding).clamp(0.0, 1.0);
    final bottom = (crop.top + crop.height + padding).clamp(0.0, 1.0);
    final x = (left * image.width).round().clamp(0, image.width - 1);
    final y = (top * image.height).round().clamp(0, image.height - 1);
    final width = ((right - left) * image.width).round().clamp(
      1,
      image.width - x,
    );
    final height = ((bottom - top) * image.height).round().clamp(
      1,
      image.height - y,
    );
    return img.copyCrop(image, x: x, y: y, width: width, height: height);
  }

  /// Adds a second OCR candidate for gallery photos where a landscape card is
  /// centered but surrounded by table/background. The original is always kept
  /// as well, so an off-center card cannot be made worse by this heuristic.
  static img.Image centerCropToCardAspect(
    img.Image image, {
    bool portrait = false,
  }) {
    const cardAspect = 1.586;
    final targetAspect = portrait ? 1 / cardAspect : cardAspect;
    final currentAspect = image.width / image.height;
    if ((currentAspect - targetAspect).abs() < 0.08) return image;

    if (currentAspect > targetAspect) {
      final width = (image.height * targetAspect).round();
      return img.copyCrop(
        image,
        x: ((image.width - width) / 2).round(),
        y: 0,
        width: width,
        height: image.height,
      );
    }
    final height = (image.width / targetAspect).round();
    return img.copyCrop(
      image,
      x: 0,
      y: ((image.height - height) / 2).round(),
      width: image.width,
      height: height,
    );
  }

  static img.Image convertToGrayscale(img.Image image) {
    return img.grayscale(image);
  }

  static img.Image enhanceContrast(img.Image image, {double contrast = 1.3}) {
    return img.adjustColor(image, contrast: contrast);
  }

  static img.Image sharpenImage(img.Image image, {double amount = 1.0}) {
    final center = 5 * amount;
    final edge = -1 * amount;

    return img.convolution(
      image,
      filter: [0, edge, 0, edge, center, edge, 0, edge, 0],
    );
  }

  static img.Image adjustBrightness(img.Image image) {
    double avgBrightness = calculateAverageBrightness(image);

    double adjustment = 0;
    if (avgBrightness < 100) {
      adjustment = (100 - avgBrightness) / 100 * 50;
    } else if (avgBrightness > 180) {
      adjustment = (180 - avgBrightness) / 100 * 30;
    }

    if (adjustment != 0) {
      return img.adjustColor(image, brightness: adjustment);
    }

    return image;
  }

  static double calculateAverageBrightness(img.Image image) {
    int totalBrightness = 0;
    int pixelCount = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        totalBrightness += ((r + g + b) / 3).round();
        pixelCount++;
      }
    }

    return pixelCount > 0 ? totalBrightness / pixelCount : 0;
  }

  static Future<ImageQuality> validateImageQuality(
    String imagePath, {
    NormalizedCardCrop? crop,
  }) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);

      if (image == null) {
        return ImageQuality(
          blurScore: 0,
          brightness: 0,
          isGoodQuality: false,
          warning: 'Failed to decode image',
        );
      }

      image = img.bakeOrientation(image);

      if (crop != null) {
        image = cropToNormalizedCard(image, crop);
      }

      final shortEdge = min(image.width, image.height);
      final longEdge = max(image.width, image.height);
      final hasEnoughPixels =
          shortEdge >= minCardShortEdge && longEdge >= minCardLongEdge;

      final blurScore = calculateBlurScore(image);
      final brightness = calculateAverageBrightness(image);
      final contrast = calculateLuminanceContrast(image);
      final glareRatio = calculateGlareRatio(image);

      String? warning;
      bool isGoodQuality = true;

      if (!hasEnoughPixels) {
        warning = 'The card is small in the photo. Move closer for more reliable text recognition.';
        isGoodQuality = false;
      } else if (blurScore < minBlurScore) {
        warning = 'Image is blurry. Please hold the camera steady.';
        isGoodQuality = false;
      } else if (brightness < minBrightness) {
        warning = 'Image is too dark. Please improve lighting or use flash.';
        isGoodQuality = false;
      } else if (brightness > maxBrightness) {
        warning =
            'Image is too bright. Please reduce lighting or turn off flash.';
        isGoodQuality = false;
      } else if (glareRatio > maxGlareRatio) {
        warning =
            'Glare is covering the card. Tilt it slightly away from the light.';
        isGoodQuality = false;
      } else if (contrast < minContrast) {
        warning = 'Card details have low contrast. Try a different angle or background.';
        isGoodQuality = false;
      }

      return ImageQuality(
        blurScore: blurScore,
        brightness: brightness,
        contrast: contrast,
        glareRatio: glareRatio,
        isGoodQuality: isGoodQuality,
        warning: warning,
      );
    } catch (e) {
      return ImageQuality(
        blurScore: 0,
        brightness: 0,
        isGoodQuality: false,
        warning: 'Error validating image: $e',
      );
    }
  }

  static double calculateBlurScore(img.Image image) {
    final gray = img.grayscale(image);
    final step = max(1, min(gray.width, gray.height) ~/ 700);
    var count = 0;
    var mean = 0.0;
    var squaredDelta = 0.0;

    // Online variance avoids allocating an integer matrix proportional to a
    // very-high-resolution camera capture.
    for (var y = step; y < gray.height - step; y += step) {
      for (var x = step; x < gray.width - step; x += step) {
        final center = gray.getPixel(x, y).r.toInt();
        final top = gray.getPixel(x, y - step).r.toInt();
        final bottom = gray.getPixel(x, y + step).r.toInt();
        final left = gray.getPixel(x - step, y).r.toInt();
        final right = gray.getPixel(x + step, y).r.toInt();
        final laplacian = (4 * center - top - bottom - left - right).abs();
        count++;
        final delta = laplacian - mean;
        mean += delta / count;
        squaredDelta += delta * (laplacian - mean);
      }
    }
    return count > 1 ? squaredDelta / (count - 1) : 0;
  }

  static double calculateLuminanceContrast(img.Image image) {
    final step = max(1, min(image.width, image.height) ~/ 500);
    var count = 0;
    var mean = 0.0;
    var squaredDelta = 0.0;
    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        final pixel = image.getPixel(x, y);
        final luminance =
            0.299 * pixel.r.toDouble() +
            0.587 * pixel.g.toDouble() +
            0.114 * pixel.b.toDouble();
        count++;
        final delta = luminance - mean;
        mean += delta / count;
        squaredDelta += delta * (luminance - mean);
      }
    }
    return count > 1 ? sqrt(squaredDelta / (count - 1)) : 0;
  }

  static double calculateGlareRatio(img.Image image) {
    final step = max(1, min(image.width, image.height) ~/ 500);
    var sampled = 0;
    var glarePixels = 0;
    for (var y = 0; y < image.height; y += step) {
      for (var x = 0; x < image.width; x += step) {
        final pixel = image.getPixel(x, y);
        final maximum = max(
          pixel.r.toInt(),
          max(pixel.g.toInt(), pixel.b.toInt()),
        );
        final minimum = min(
          pixel.r.toInt(),
          min(pixel.g.toInt(), pixel.b.toInt()),
        );
        if (maximum >= 245 && maximum - minimum <= 14) glarePixels++;
        sampled++;
      }
    }
    return sampled == 0 ? 0 : glarePixels / sampled;
  }
}

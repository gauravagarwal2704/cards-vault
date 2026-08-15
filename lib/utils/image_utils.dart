import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

class ImageQuality {
  final double blurScore;
  final double brightness;
  final bool isGoodQuality;
  final String? warning;

  ImageQuality({
    required this.blurScore,
    required this.brightness,
    required this.isGoodQuality,
    this.warning,
  });
}

class ImageUtils {
  static const double minBlurScore = 100.0;
  static const double minBrightness = 40.0;
  static const double maxBrightness = 220.0;
  static const int minWidth = 800;
  static const int minHeight = 500;

  static Future<img.Image?> preprocessForOCR(String imagePath, {Rect? cardFrame, bool forEmbossedText = false}) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      
      if (image == null) return null;

      if (cardFrame != null) {
        image = cropToCardFrame(image, cardFrame);
      }

      if (forEmbossedText) {
        // Special preprocessing for embossed card numbers
        // 1. Increase contrast significantly to make shadows visible
        image = enhanceContrast(image, contrast: 2.5);
        
        // 2. Convert to grayscale
        image = img.grayscale(image);
        
        // 3. Apply edge detection to highlight embossed edges
        image = sharpenImage(image, amount: 2.0);
        
        // 4. Adjust brightness
        image = adjustBrightness(image);
        
        // 5. Apply adaptive threshold to create clear black/white text
        image = _applyAdaptiveThreshold(image);
      } else {
        image = enhanceContrast(image, contrast: 1.5);
        image = sharpenImage(image);
        image = adjustBrightness(image);
      }

      return image;
    } catch (e) {
      return null;
    }
  }
  
  static img.Image _applyAdaptiveThreshold(img.Image image) {
    // Calculate local threshold for each pixel
    final result = img.Image(width: image.width, height: image.height);
    const int windowSize = 15;
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        int sum = 0;
        int count = 0;
        
        // Calculate average in local window
        for (int wy = max(0, y - windowSize); wy < min(image.height, y + windowSize); wy++) {
          for (int wx = max(0, x - windowSize); wx < min(image.width, x + windowSize); wx++) {
            final pixel = image.getPixel(wx, wy);
            sum += pixel.r.toInt();
            count++;
          }
        }
        
        final threshold = sum ~/ count;
        final pixel = image.getPixel(x, y);
        final value = pixel.r.toInt() > threshold - 10 ? 255 : 0;
        
        result.setPixelRgba(x, y, value, value, value, 255);
      }
    }
    
    return result;
  }

  static img.Image cropToCardFrame(img.Image image, Rect cardFrame) {
    int x = (cardFrame.left * image.width).toInt().clamp(0, image.width - 1);
    int y = (cardFrame.top * image.height).toInt().clamp(0, image.height - 1);
    int width = (cardFrame.width * image.width).toInt().clamp(1, image.width - x);
    int height = (cardFrame.height * image.height).toInt().clamp(1, image.height - y);

    return img.copyCrop(image, x: x, y: y, width: width, height: height);
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
      filter: [
        0, edge, 0,
        edge, center, edge,
        0, edge, 0
      ],
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

  static Future<ImageQuality> validateImageQuality(String imagePath) async {
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

      if (image.width < minWidth || image.height < minHeight) {
        return ImageQuality(
          blurScore: 0,
          brightness: 0,
          isGoodQuality: false,
          warning: 'Image resolution too low. Please move closer to the card.',
        );
      }

      double blurScore = calculateBlurScore(image);
      double brightness = calculateAverageBrightness(image);

      String? warning;
      bool isGoodQuality = true;

      if (blurScore < minBlurScore) {
        warning = 'Image is blurry. Please hold the camera steady.';
        isGoodQuality = false;
      } else if (brightness < minBrightness) {
        warning = 'Image is too dark. Please improve lighting or use flash.';
        isGoodQuality = false;
      } else if (brightness > maxBrightness) {
        warning = 'Image is too bright. Please reduce lighting or turn off flash.';
        isGoodQuality = false;
      }

      return ImageQuality(
        blurScore: blurScore,
        brightness: brightness,
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
    img.Image gray = img.grayscale(image);
    
    List<List<int>> laplacian = List.generate(
      gray.height,
      (y) => List.generate(gray.width, (x) => 0),
    );

    for (int y = 1; y < gray.height - 1; y++) {
      for (int x = 1; x < gray.width - 1; x++) {
        final center = gray.getPixel(x, y).r.toInt();
        final top = gray.getPixel(x, y - 1).r.toInt();
        final bottom = gray.getPixel(x, y + 1).r.toInt();
        final left = gray.getPixel(x - 1, y).r.toInt();
        final right = gray.getPixel(x + 1, y).r.toInt();
        
        laplacian[y][x] = (4 * center - top - bottom - left - right).abs();
      }
    }

    double sum = 0;
    int count = 0;
    for (int y = 1; y < gray.height - 1; y++) {
      for (int x = 1; x < gray.width - 1; x++) {
        sum += laplacian[y][x];
        count++;
      }
    }
    
    double mean = count > 0 ? sum / count : 0;
    
    double variance = 0;
    for (int y = 1; y < gray.height - 1; y++) {
      for (int x = 1; x < gray.width - 1; x++) {
        variance += pow(laplacian[y][x] - mean, 2);
      }
    }
    
    return count > 0 ? variance / count : 0;
  }

  static Future<File> savePreprocessedImage(img.Image image, String originalPath) async {
    final bytes = img.encodeJpg(image, quality: 95);
    final file = File(originalPath.replaceAll('.jpg', '_processed.jpg'));
    await file.writeAsBytes(bytes);
    return file;
  }

  static String correctOCRCharacters(String text) {
    return text
        // Common OCR errors for embossed numbers
        .replaceAll('O', '0')
        .replaceAll('o', '0')
        .replaceAll('I', '1')
        .replaceAll('i', '1')
        .replaceAll('l', '1')
        .replaceAll('L', '1')
        .replaceAll('|', '1')
        .replaceAll('S', '5')
        .replaceAll('s', '5')
        .replaceAll('B', '8')
        .replaceAll('b', '6')  // 'b' often misread as '6'
        .replaceAll('G', '6')
        .replaceAll('Z', '2')
        .replaceAll('z', '2')
        .replaceAll('T', '7')
        .replaceAll('D', '0')
        .replaceAll('Q', '0');
  }
}

class Rect {
  final double left;
  final double top;
  final double width;
  final double height;

  Rect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}


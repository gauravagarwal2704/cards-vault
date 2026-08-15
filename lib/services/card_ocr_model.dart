import 'dart:io';
import 'package:image/image.dart' as img;

class CardOCRModel {
  static const int inputWidth = 640;
  static const int inputHeight = 400;
  
  Future<Map<String, dynamic>> detectCardRegions(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      
      if (image == null) {
        return {'success': false, 'error': 'Failed to decode image'};
      }

      img.Image resized = img.copyResize(
        image,
        width: inputWidth,
        height: inputHeight,
      );

      Map<String, Rect> regions = _detectTextRegions(resized);

      Map<String, img.Image> croppedRegions = {};
      regions.forEach((key, rect) {
        croppedRegions[key] = _cropRegion(image, rect, image.width, image.height);
      });

      return {
        'success': true,
        'regions': regions,
        'croppedImages': croppedRegions,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Map<String, Rect> _detectTextRegions(img.Image image) {
    Map<String, Rect> regions = {};

    double cardNumberTop = 0.35;
    double cardNumberHeight = 0.15;
    double cardNumberLeft = 0.05;
    double cardNumberWidth = 0.90;

    regions['cardNumber'] = Rect(
      left: cardNumberLeft,
      top: cardNumberTop,
      width: cardNumberWidth,
      height: cardNumberHeight,
    );

    double expiryTop = 0.55;
    double expiryHeight = 0.12;
    double expiryLeft = 0.60;
    double expiryWidth = 0.35;

    regions['expiry'] = Rect(
      left: expiryLeft,
      top: expiryTop,
      width: expiryWidth,
      height: expiryHeight,
    );

    double nameTop = 0.70;
    double nameHeight = 0.12;
    double nameLeft = 0.05;
    double nameWidth = 0.60;

    regions['name'] = Rect(
      left: nameLeft,
      top: nameTop,
      width: nameWidth,
      height: nameHeight,
    );

    return regions;
  }

  img.Image _cropRegion(img.Image image, Rect region, int fullWidth, int fullHeight) {
    int x = (region.left * fullWidth).toInt().clamp(0, fullWidth - 1);
    int y = (region.top * fullHeight).toInt().clamp(0, fullHeight - 1);
    int width = (region.width * fullWidth).toInt().clamp(1, fullWidth - x);
    int height = (region.height * fullHeight).toInt().clamp(1, fullHeight - y);

    return img.copyCrop(image, x: x, y: y, width: width, height: height);
  }

  img.Image preprocessRegion(img.Image region, {bool forNumbers = true}) {
    region = img.adjustColor(region, contrast: 1.8, brightness: 10);
    
    region = img.grayscale(region);
    
    int threshold = forNumbers ? 140 : 120;
    for (int y = 0; y < region.height; y++) {
      for (int x = 0; x < region.width; x++) {
        final pixel = region.getPixel(x, y);
        final luminance = pixel.r.toInt();
        final newColor = luminance > threshold ? 255 : 0;
        region.setPixelRgba(x, y, newColor, newColor, newColor, 255);
      }
    }

    region = img.copyResize(region, width: region.width * 2, height: region.height * 2);

    return region;
  }

  Future<String> saveRegionImage(img.Image region, String originalPath, String regionName) async {
    final bytes = img.encodeJpg(region, quality: 95);
    final file = File(originalPath.replaceAll('.jpg', '_$regionName.jpg'));
    await file.writeAsBytes(bytes);
    return file.path;
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


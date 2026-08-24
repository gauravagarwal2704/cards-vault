import 'dart:io';

import 'package:cards_wallet/utils/image_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('phone-sized card crops retain real quality measurements', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'card_quality_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    Future<File> writePattern(String name, int width, int height) async {
      final image = img.Image(width: width, height: height);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final bright = ((x ~/ 12) + (y ~/ 12)).isEven;
          final value = bright ? 210 : 35;
          image.setPixelRgb(x, y, value, value, value);
        }
      }
      final file = File('${tempDirectory.path}/$name.png');
      await file.writeAsBytes(img.encodePng(image));
      return file;
    }

    final usableCrop = await writePattern('usable', 360, 560);
    final usableQuality = await ImageUtils.validateImageQuality(
      usableCrop.path,
    );
    expect(usableQuality.brightness, greaterThan(0));
    expect(usableQuality.contrast, greaterThan(0));
    expect(usableQuality.blurScore, greaterThan(0));
    expect(usableQuality.warning, isNot(contains('resolution too low')));

    final smallCrop = await writePattern('small', 120, 180);
    final smallQuality = await ImageUtils.validateImageQuality(smallCrop.path);
    expect(smallQuality.brightness, greaterThan(0));
    expect(smallQuality.contrast, greaterThan(0));
    expect(smallQuality.blurScore, greaterThan(0));
    expect(smallQuality.warning, contains('small in the photo'));
  });
}

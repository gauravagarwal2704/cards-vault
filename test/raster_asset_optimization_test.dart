import 'dart:io';

import 'package:cards_wallet/models/app_icon_option.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test('runtime app-icon artwork is bounded and WebP encoded', () {
    var totalBytes = 0;

    for (final option in AppIconCatalog.options) {
      expect(option.assetPath, endsWith('.webp'), reason: option.id);
      final file = File(option.assetPath);
      expect(file.existsSync(), isTrue, reason: option.assetPath);

      final bytes = file.readAsBytesSync();
      totalBytes += bytes.length;
      final decoded = image.decodeImage(bytes);
      expect(decoded, isNotNull, reason: option.assetPath);
      expect(decoded!.width, 768, reason: option.assetPath);
      expect(decoded.height, 768, reason: option.assetPath);
      expect(bytes.length, lessThan(30 * 1024), reason: option.assetPath);
    }

    expect(totalBytes, lessThan(200 * 1024));
    expect(
      Directory('assets/branding')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.png')),
      isEmpty,
    );
  });
}

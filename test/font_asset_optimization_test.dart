import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const expectedFonts = {
    'Outfit-Light.ttf': 300,
    'Outfit-Regular.ttf': 400,
    'Outfit-Medium.ttf': 500,
    'Outfit-SemiBold.ttf': 600,
    'Outfit-Bold.ttf': 700,
  };

  test('only production Outfit weights are bundled', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final files = Directory('assets/fonts')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.ttf'))
        .toList();

    expect(
      files.map((file) => file.uri.pathSegments.last).toSet(),
      expectedFonts.keys.toSet(),
    );
    for (final entry in expectedFonts.entries) {
      expect(pubspec, contains('asset: assets/fonts/${entry.key}'));
      expect(pubspec, contains('weight: ${entry.value}'));
      final file = File('assets/fonts/${entry.key}');
      expect(file.lengthSync(), lessThan(32 * 1024), reason: entry.key);
    }
  });

  test('production code cannot silently restore the removed 800 face', () {
    final productionSource = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(productionSource, isNot(contains('FontWeight.w800')));
    expect(File('assets/fonts/Outfit-ExtraBold.ttf').existsSync(), isFalse);
    expect(File('lib/widgets/tipping_card.dart').existsSync(), isFalse);
  });
}

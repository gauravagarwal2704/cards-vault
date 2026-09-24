import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const scannerRoot = 'android/stripe-cardscan-local/stripecardscan/src/main';

  test('vendored scanner exposes only the CardVault activity entry point', () {
    final manifest = File('$scannerRoot/AndroidManifest.xml')
        .readAsStringSync();

    expect(RegExp(r'<activity\b').allMatches(manifest), hasLength(1));
    expect(manifest, contains('.cardscan.CardScanActivity'));
    expect(manifest, contains('android:exported="false"'));
    expect(manifest, isNot(contains('CardScanFragment')));
    expect(manifest, isNot(contains('CardScanSheet')));
  });

  test('R8-proven legacy scanner sources and resources stay removed', () {
    const removedPaths = <String>[
      '$scannerRoot/java/com/stripe/android/stripecardscan/cardscan/CardScanConfiguration.kt',
      '$scannerRoot/java/com/stripe/android/stripecardscan/cardscan/exception/UnknownScanException.kt',
      '$scannerRoot/java/com/stripe/android/stripecardscan/payment/card/PanFormatter.kt',
      '$scannerRoot/java/com/stripe/android/stripecardscan/payment/card/ScannedCard.kt',
      '$scannerRoot/res/layout/stripe_fragment_cardscan.xml',
      '$scannerRoot/res/drawable/stripe_camera_swap_light.xml',
      '$scannerRoot/res/drawable/stripe_card_background_wrong.xml',
      '$scannerRoot/res/drawable/stripe_card_border_cardverify_found_long.xml',
      '$scannerRoot/res/drawable/stripe_close_button_light.xml',
      '$scannerRoot/res/drawable/stripe_flash_off_light.xml',
      '$scannerRoot/res/drawable/stripe_flash_on_light.xml',
      '$scannerRoot/res/drawable/stripe_lock_dark.xml',
      '$scannerRoot/res/drawable/stripe_lock_light.xml',
      '$scannerRoot/res/drawable/stripe_paymentsheet_card_border_not_found.xml',
      '$scannerRoot/res/drawable/stripe_paymentsheet_close_button.xml',
      '$scannerRoot/res/drawable/stripe_rounded_button_light.xml',
    ];

    for (final path in removedPaths) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }

    final activity = File(
      '$scannerRoot/java/com/stripe/android/stripecardscan/cardscan/CardScanActivity.kt',
    ).readAsStringSync();
    expect(activity, isNot(contains('CardScanResultListener')));
    expect(activity, isNot(contains('cardScanComplete')));
    expect(activity, isNot(contains('INTENT_PARAM_REQUEST')));
    expect(activity, isNot(contains('INTENT_PARAM_RESULT')));
  });

  test('scanner packages only the single OCR model used by CardVault', () {
    final assets = Directory('$scannerRoot/assets')
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.path)
        .where((path) => path.endsWith('.tflite'))
        .toList();

    expect(assets, hasLength(1));
    expect(assets.single, endsWith('darknite_1_1_1_16.tflite'));
  });
}

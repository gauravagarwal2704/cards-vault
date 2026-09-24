import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CardScan pins one supported CPU-only LiteRT runtime', () {
    final baseGradle = File(
      'android/stripe-cardscan-local/ml-core-base/build.gradle',
    ).readAsStringSync();
    final implementationGradle = File(
      'android/stripe-cardscan-local/ml-core-cardscan/build.gradle',
    ).readAsStringSync();
    final scannerGradle = File(
      'android/stripe-cardscan-local/stripecardscan/build.gradle',
    ).readAsStringSync();
    final interpreterOptions = File(
      'android/stripe-cardscan-local/ml-core-base/src/main/java/com/stripe/android/mlcore/base/InterpreterOptionsWrapper.kt',
    ).readAsStringSync();
    final appGradle = File('android/app/build.gradle').readAsStringSync();

    expect(
      implementationGradle,
      contains('com.google.ai.edge.litert:litert:2.2.0'),
    );
    expect(baseGradle, isNot(contains('com.google.ai.edge.litert:litert:')));
    expect(scannerGradle, isNot(contains('com.google.ai.edge.litert:litert:')));
    expect(
      appGradle,
      contains("excludes += ['**/libLiteRtClGlAccelerator.so']"),
    );
    expect(appGradle, contains('useLegacyPackaging = true'));
    expect(
      implementationGradle,
      isNot(contains('com.google.android.gms:play-services-tflite')),
    );
    expect(interpreterOptions, isNot(contains('useNNAPI')));
  });

  test('release scanner footprint is measured from split APK contents', () {
    final verifier = File('tool/verify_scanner_apk_size.dart');
    expect(verifier.existsSync(), isTrue);
    final source = verifier.readAsStringSync();

    expect(source, contains('scannerCompressedBudgetBytes'));
    expect(source, contains('libLiteRt.so'));
    expect(source, contains('liblitert_jni.so'));
    expect(source, contains('darknite_1_1_1_16.tflite'));
    expect(source, contains('exactly one ABI'));
  });

  test('LiteRT optional delivery capabilities are removed', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    expect(
      manifest,
      contains('android.permission.FOREGROUND_SERVICE_DATA_SYNC'),
    );
    expect(
      RegExp(
        r'android:name="android\.permission\.FOREGROUND_SERVICE_DATA_SYNC"\s+tools:node="remove"',
      ).hasMatch(manifest),
      isTrue,
    );
    expect(
      RegExp(r'android:name="android\.hardware\.npu"\s+tools:node="remove"')
          .hasMatch(manifest),
      isTrue,
    );
  });

  test('release shrinking preserves WorkManager Room construction', () {
    final proguardRules = File('android/app/proguard-rules.pro')
        .readAsStringSync();

    expect(
      proguardRules,
      contains('-keepclassmembers class androidx.work.impl.WorkDatabase_Impl'),
    );
    expect(proguardRules, contains('public <init>();'));
  });
}

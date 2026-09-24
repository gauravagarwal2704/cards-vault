import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android application and network policy reject cleartext traffic', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final networkPolicy = File(
      'android/app/src/main/res/xml/network_security_config.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:usesCleartextTraffic="false"'));
    expect(
      manifest,
      contains('android:networkSecurityConfig="@xml/network_security_config"'),
    );
    expect(networkPolicy, contains('cleartextTrafficPermitted="false"'));
    expect(networkPolicy, isNot(contains('cleartextTrafficPermitted="true"')));
    expect(networkPolicy, isNot(contains('<domain-config')));
    expect(networkPolicy, isNot(contains('src="user"')));
  });

  test('still-image camera use removes microphone permission', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    expect(
      RegExp(
        r'android:name="android\.permission\.RECORD_AUDIO"\s+tools:node="remove"',
      ).hasMatch(manifest),
      isTrue,
    );
  });

  test('production manifest cannot transmit data or run after boot', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    for (final permission in <String>[
      'INTERNET',
      'ACCESS_NETWORK_STATE',
      'WAKE_LOCK',
      'RECEIVE_BOOT_COMPLETED',
    ]) {
      expect(
        RegExp(
          'android:name="android\\.permission\\.$permission"\\s+'
          'tools:node="remove"',
        ).hasMatch(manifest),
        isTrue,
        reason: '$permission must stay out of production builds',
      );
    }
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _readProperties(String path) {
  final values = <String, String>{};
  for (final rawLine in File(path).readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    values[line.substring(0, separator)] = line.substring(separator + 1);
  }
  return values;
}

void main() {
  const root = 'android/stripe-cardscan-local';

  test('vendored scanner provenance is immutable and complete', () {
    final provenance = _readProperties('$root/UPSTREAM.properties');

    expect(
      provenance['upstreamRepository'],
      'https://github.com/stripe/stripe-android',
    );
    expect(provenance['upstreamTag'], 'v21.28.1');
    expect(provenance['upstreamTagObject'], matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(
      provenance['upstreamCommit'],
      '608adb7515db07c758303bd95b9013e063316f8e',
    );
    expect(int.parse(provenance['forkRevision']!), greaterThan(0));
    final cadence = int.parse(provenance['reviewCadenceDays']!);
    final lastReviewed = DateTime.parse(provenance['lastReviewed']!);
    final today = DateTime.now().toUtc();
    final reviewAge = today.difference(lastReviewed).inDays;
    expect(cadence, lessThanOrEqualTo(90));
    expect(reviewAge, inInclusiveRange(0, cadence));
  });

  test('Gradle resolves only the isolated local scanner modules', () {
    final settings = File('android/settings.gradle').readAsStringSync();
    final build = File('$root/stripecardscan/build.gradle').readAsStringSync();

    expect(settings, contains('UPSTREAM.properties'));
    for (final module in const [
      'stripe-cardscan-camera-core',
      'stripe-cardscan-ml-core-base',
      'stripe-cardscan-ml-core-cardscan',
      'stripe-cardscan-local',
    ]) {
      expect(settings, contains('include ":$module"'), reason: module);
      expect(
        settings,
        contains('project(":$module").projectDir'),
        reason: module,
      );
    }
    expect(build, contains('com.cardswallet.vendored.stripe'));
    expect(build, isNot(contains('com.stripe:stripecardscan')));
  });

  test('every production delta category and upgrade gate is documented', () {
    final inventory = File('$root/LOCAL_DELTAS.md').readAsStringSync();
    final readme = File('$root/README.md').readAsStringSync();

    for (final path in const [
      'CameraAdapter.kt',
      'CameraXAdapter.kt',
      'CameraPermissionCheckingActivity.kt',
      'InterpreterOptionsWrapper.kt',
      'InterpreterWrapperImpl.kt',
      'CardScanActivity.kt',
      'CardScanFlow.kt',
      'MainLoopAggregator.kt',
      'SSDOcr.kt',
      'AndroidManifest.xml',
      'LiteRtModelSmokeTest.kt',
    ]) {
      expect(inventory, contains(path), reason: path);
    }
    for (final gate in const [
      'every 90 days',
      'security release',
      'full commit SHA',
      'flutter analyze',
      'split-ABI release build',
      'physical arm64 device',
    ]) {
      expect(readme, contains(gate), reason: gate);
    }
  });
}

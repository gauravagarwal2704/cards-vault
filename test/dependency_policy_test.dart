import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('direct package constraints exactly match the reviewed lockfile', () {
    final constraints = _packageConstraints(File('pubspec.yaml'));
    final locked = _lockedVersions(File('pubspec.lock'));
    final exactVersion = RegExp(
      r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
    );

    for (final entry in constraints.entries) {
      expect(entry.value, matches(exactVersion), reason: entry.key);
      expect(entry.value, locked[entry.key], reason: entry.key);
    }
  });

  test('automated Pub and Android update windows are configured', () {
    final config = File('.github/dependabot.yml').readAsStringSync();

    expect(config, contains('package-ecosystem: "pub"'));
    expect(config, contains('directory: "/"'));
    expect(config, contains('package-ecosystem: "gradle"'));
    expect(config, contains('directory: "/android"'));
    expect(RegExp('interval: "weekly"').allMatches(config), hasLength(2));
    expect(RegExp('timezone: "Asia/Kolkata"').allMatches(config), hasLength(2));
    expect(config, contains('update-types:'));
    expect(config, contains('"minor"'));
    expect(config, contains('"patch"'));
  });

  test('dependency review policy contains every release gate', () {
    final policy = File('docs/dependency-maintenance.md')
        .readAsStringSync()
        .toLowerCase();

    for (final gate in const [
      'changelog',
      'security advisory',
      'pubspec.lock',
      'transitive packages',
      'flutter analyze',
      'flutter test',
      'split-per-abi',
      'apk size delta',
      'rollback',
    ]) {
      expect(policy, contains(gate), reason: gate);
    }
  });
}

Map<String, String> _packageConstraints(File pubspec) {
  final constraints = <String, String>{};
  var inPackages = false;
  final package = RegExp(r'^  ([a-z0-9_]+):\s+([^\s#]+)');

  for (final line in pubspec.readAsLinesSync()) {
    if (line == 'dependencies:' || line == 'dev_dependencies:') {
      inPackages = true;
      continue;
    }
    if (line == 'flutter:') break;
    if (!inPackages) continue;
    final match = package.firstMatch(line);
    if (match == null) continue;
    constraints[match.group(1)!] = match.group(2)!;
  }

  return constraints;
}

Map<String, String> _lockedVersions(File lockfile) {
  final versions = <String, String>{};
  final package = RegExp(r'^  ([a-z0-9_]+):$');
  final version = RegExp(r'^    version: "([^"]+)"$');
  String? currentPackage;

  for (final line in lockfile.readAsLinesSync()) {
    final packageMatch = package.firstMatch(line);
    if (packageMatch != null) {
      currentPackage = packageMatch.group(1)!;
      continue;
    }
    final versionMatch = version.firstMatch(line);
    if (currentPackage != null && versionMatch != null) {
      versions[currentPackage] = versionMatch.group(1)!;
    }
  }

  return versions;
}

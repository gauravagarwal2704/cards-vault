import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, dynamic> allowlist;

  setUpAll(() {
    allowlist = jsonDecode(
      File('tool/asset_allowlist.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  test('every source asset is explicitly allowlisted', () {
    final directoryRules =
        (allowlist['packagedDirectories'] as Map<String, dynamic>).map(
          (path, extensions) => MapEntry(
            path,
            (extensions as List<dynamic>).cast<String>().toSet(),
          ),
        );
    final fileRules = <String>{
      ...(allowlist['packagedFiles'] as List<dynamic>).cast<String>(),
      ...(allowlist['sourceOnlyFiles'] as List<dynamic>).cast<String>(),
    };

    final assets =
        Directory('assets')
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .map((file) => file.path)
            .toList()
          ..sort();

    for (final asset in assets) {
      if (fileRules.contains(asset)) continue;
      final matchingRules = directoryRules.entries.where(
        (rule) => asset.startsWith(rule.key),
      );
      expect(matchingRules, hasLength(1), reason: 'Unlisted asset: $asset');
      expect(
        matchingRules.single.value,
        contains(_extension(asset)),
        reason: 'Disallowed asset type: $asset',
      );
    }

    for (final file in fileRules) {
      expect(
        File(file).existsSync(),
        isTrue,
        reason: 'Missing allowlisted file: $file',
      );
    }
  });

  test('pubspec packages exactly the allowlisted runtime assets', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final directories =
        (allowlist['packagedDirectories'] as Map<String, dynamic>).keys;
    final packagedFiles = (allowlist['packagedFiles'] as List<dynamic>)
        .cast<String>();
    final sourceOnlyFiles = (allowlist['sourceOnlyFiles'] as List<dynamic>)
        .cast<String>();

    final declaredAssetDirectories = RegExp(
      r'^    - (assets/.*/)$',
      multiLine: true,
    ).allMatches(pubspec).map((match) => match.group(1)!).toSet();
    expect(declaredAssetDirectories, directories.toSet());

    for (final file in packagedFiles) {
      expect(pubspec, contains('- asset: $file'));
    }
    for (final file in sourceOnlyFiles) {
      expect(pubspec, isNot(contains(file)));
    }
  });

  test(
    'generated reports, captures, and scratch artifacts cannot drift in',
    () {
      final ignore = File('.gitignore').readAsStringSync();
      for (final rule in <String>[
        '**/build/reports/',
        '/reports/',
        '**/captures/',
        '**/screenshots/',
        '**/scratch/',
        '**/__pycache__/',
        '*.trace',
        '*.hprof',
      ]) {
        expect(ignore, contains(rule), reason: 'Missing ignore rule: $rule');
      }

      final tracked = Process.runSync('git', <String>['ls-files']);
      expect(tracked.exitCode, 0, reason: tracked.stderr.toString());
      final trackedPaths = const LineSplitter()
          .convert(tracked.stdout.toString())
          .where((path) => File(path).existsSync())
          .where(_isGeneratedArtifact)
          .toList();
      expect(trackedPaths, isEmpty, reason: 'Tracked generated artifacts');
    },
  );
}

String _extension(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot).toLowerCase();
}

bool _isGeneratedArtifact(String path) {
  final normalized = path.toLowerCase();
  return normalized.contains('/build/reports/') ||
      normalized == 'reports' ||
      normalized.startsWith('reports/') ||
      normalized.contains('/captures/') ||
      normalized.startsWith('captures/') ||
      normalized.contains('/screenshots/') ||
      normalized.startsWith('screenshots/') ||
      normalized.contains('/scratch/') ||
      normalized.startsWith('scratch/') ||
      normalized.contains('/__pycache__/') ||
      normalized.endsWith('.pyc') ||
      normalized.endsWith('.pyo') ||
      normalized.endsWith('.trace') ||
      normalized.endsWith('.hprof') ||
      normalized.endsWith('.profraw') ||
      normalized.endsWith('.bak') ||
      normalized.endsWith('.orig');
}

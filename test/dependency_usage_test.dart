import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every direct Dart dependency is reachable from production code', () {
    final declared = _directDependencies(File('pubspec.yaml'))
      ..remove('flutter');
    final imported = <String>{};
    final packageImport = RegExp(r"package:([a-zA-Z0-9_]+)/");

    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      for (final match in packageImport.allMatches(file.readAsStringSync())) {
        imported.add(match.group(1)!);
      }
    }

    expect(
      declared.difference(imported),
      isEmpty,
      reason: 'Remove unused direct dependencies from pubspec.yaml.',
    );
  });
}

Set<String> _directDependencies(File pubspec) {
  final dependencies = <String>{};
  var inDependencies = false;
  final directEntry = RegExp(r'^  ([a-z0-9_]+):');

  for (final line in pubspec.readAsLinesSync()) {
    if (line == 'dependencies:') {
      inDependencies = true;
      continue;
    }
    if (line == 'dev_dependencies:') break;
    if (!inDependencies) continue;
    final match = directEntry.firstMatch(line);
    if (match != null) dependencies.add(match.group(1)!);
  }

  return dependencies;
}

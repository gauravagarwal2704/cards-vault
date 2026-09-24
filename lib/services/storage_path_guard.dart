import 'dart:io';

import 'package:path_provider/path_provider.dart';

final RegExp _safeStorageIdentifier = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$',
);

/// Rejects identifiers that could alter a filesystem path or collide with a
/// non-card secure-storage record.
String requireSafeStorageIdentifier(String value, {required String label}) {
  if (!_safeStorageIdentifier.hasMatch(value) ||
      value == '.' ||
      value == '..' ||
      (label == 'card ID' && value == 'groups')) {
    throw FormatException('Invalid $label in backup or wallet data');
  }
  return value;
}

/// Resolves a per-card media directory and proves that its canonical location
/// remains under the requested app-private storage root.
Future<Directory> containedCardStorageDirectory(
  String storageDirectory,
  String cardId, {
  bool create = false,
}) async {
  requireSafeStorageIdentifier(cardId, label: 'card ID');

  final documents = await getApplicationDocumentsDirectory();
  if (create && !await documents.exists()) {
    await documents.create(recursive: true);
  }
  if (!await documents.exists()) {
    return Directory('${documents.absolute.path}/$storageDirectory/$cardId');
  }
  final canonicalDocuments = Directory(await documents.resolveSymbolicLinks());
  final root = Directory('${canonicalDocuments.path}/$storageDirectory');
  if (create && !await root.exists()) await root.create(recursive: true);

  if (!await root.exists()) {
    return Directory('${root.absolute.path}/$cardId');
  }

  final canonicalRoot = Directory(await root.resolveSymbolicLinks());
  _requireContained(canonicalDocuments.path, canonicalRoot.path);
  var candidate = Directory('${canonicalRoot.path}/$cardId');
  if (create && !await candidate.exists()) {
    await candidate.create(recursive: false);
  }

  if (await candidate.exists()) {
    candidate = Directory(await candidate.resolveSymbolicLinks());
  }
  _requireContained(canonicalRoot.path, candidate.path);
  return candidate;
}

/// Ensures an existing file path is contained by an app-private media root.
Future<bool> isContainedInStorageDirectory(
  String storageDirectory,
  String filePath,
) async {
  final documents = await getApplicationDocumentsDirectory();
  if (!await documents.exists()) return false;
  final canonicalDocuments = await documents.resolveSymbolicLinks();
  final root = Directory('$canonicalDocuments/$storageDirectory');
  final file = File(filePath);
  if (!await root.exists() || !await file.exists()) return false;

  try {
    final canonicalRoot = await root.resolveSymbolicLinks();
    _requireContained(canonicalDocuments, canonicalRoot);
    final canonicalFile = await file.resolveSymbolicLinks();
    _requireContained(canonicalRoot, canonicalFile);
    return true;
  } on FileSystemException {
    return false;
  } on FormatException {
    return false;
  }
}

void _requireContained(String rootPath, String candidatePath) {
  final root = Directory(rootPath).absolute.path;
  final candidate = File(candidatePath).absolute.path;
  final prefix = '$root${Platform.pathSeparator}';
  if (!candidate.startsWith(prefix)) {
    throw const FormatException('Storage path escapes its permitted root');
  }
}

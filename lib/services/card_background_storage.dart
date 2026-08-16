import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Stores user-selected card artwork outside secure metadata storage.
///
/// Each saved background gets a unique filename so an edit can be committed
/// before the previous image is removed. This keeps the old card intact if a
/// save fails halfway through.
class CardBackgroundStorage {
  static const String backupFileName = '__card_background__';

  Future<String> saveBackground(String cardId, File source) async {
    final bytes = await source.readAsBytes();
    final extension = _safeExtension(source.path);
    return saveBackgroundBytes(cardId, bytes, extension: extension);
  }

  Future<String> saveBackgroundBytes(
    String cardId,
    Uint8List bytes, {
    String extension = '.img',
  }) async {
    final directory = await _cardDirectory(cardId);
    await directory.create(recursive: true);
    final safeExtension = _safeExtension('file$extension');
    final file = File(
      '${directory.path}/background_${DateTime.now().microsecondsSinceEpoch}$safeExtension',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Uint8List?> loadBytes(String? path) async {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> deleteBackground(String cardId, String? path) async {
    if (path == null || path.isEmpty) return;
    final directory = await _cardDirectory(cardId);
    final expectedPrefix =
        '${directory.absolute.path}${Platform.pathSeparator}';
    final file = File(path).absolute;
    if (!file.path.startsWith(expectedPrefix)) return;
    if (await file.exists()) await file.delete();
  }

  Future<void> deleteAllForCard(String cardId) async {
    final directory = await _cardDirectory(cardId);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<Directory> _cardDirectory(String cardId) async {
    final root = await getApplicationDocumentsDirectory();
    return Directory('${root.path}/card_backgrounds/$cardId');
  }

  String _safeExtension(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return '.img';
    final extension = name.substring(dot).toLowerCase();
    if (!RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(extension)) return '.img';
    return extension;
  }
}

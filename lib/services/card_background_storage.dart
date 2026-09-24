import 'dart:io';
import 'dart:typed_data';

import 'storage_path_guard.dart';
import 'app_log_service.dart';

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
    return AppLogService.instance.trace('Storage', 'Save card background', () async {
      final directory = await _cardDirectory(cardId, create: true);
      final safeExtension = _safeExtension('file$extension');
      final file = File(
        '${directory.path}/background_${DateTime.now().microsecondsSinceEpoch}$safeExtension',
      );
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    }, details: {'byteCount': bytes.length});
  }

  Future<Uint8List?> loadBytes(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists() ||
          !await isContainedInStorageDirectory('card_backgrounds', path)) {
        return null;
      }
      return await file.readAsBytes();
    } catch (error, stackTrace) {
      AppLogService.instance.recordFailure(
        'Load card background',
        error,
        stackTrace,
        category: 'Failure/Storage',
      );
      return null;
    }
  }

  Future<void> deleteBackground(String cardId, String? path) async {
    if (path == null || path.isEmpty) return;
    await AppLogService.instance.trace(
      'Storage',
      'Delete card background',
      () async {
        final directory = await _cardDirectory(cardId);
        if (!await directory.exists()) return;
        final file = File(path);
        if (!await isContainedInStorageDirectory('card_backgrounds', path)) {
          return;
        }
        final canonicalDirectory = await directory.resolveSymbolicLinks();
        final canonicalFile = await file.resolveSymbolicLinks();
        final expectedPrefix = '$canonicalDirectory${Platform.pathSeparator}';
        if (!canonicalFile.startsWith(expectedPrefix)) return;
        if (await file.exists()) await file.delete();
      },
    );
  }

  Future<void> deleteAllForCard(String cardId) async {
    await AppLogService.instance.trace(
      'Storage',
      'Delete all card backgrounds',
      () async {
        final directory = await _cardDirectory(cardId);
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      },
    );
  }

  Future<Directory> _cardDirectory(String cardId, {bool create = false}) async {
    return containedCardStorageDirectory(
      'card_backgrounds',
      cardId,
      create: create,
    );
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

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Captures the complete wallet state that an import can mutate and can restore
/// it if any part of the commit fails.
///
/// Secure-storage values remain in memory. Media files are copied only to the
/// app's temporary directory and are removed when the transaction finishes.
class BackupImportTransaction {
  BackupImportTransaction(this._secureStorage);

  static const _cardsListKey = 'saved_cards_list';
  static const _cardPrefix = 'card_';
  static const _groupsKey = 'card_groups';
  static const _mediaDirectories = ['card_attachments', 'card_backgrounds'];

  final FlutterSecureStorage _secureStorage;
  final Map<String, String> _secureValues = {};
  Directory? _documentsDirectory;
  Directory? _snapshotDirectory;
  bool _captured = false;

  Future<void> capture() async {
    if (_captured) {
      throw StateError('Backup import transaction was already captured');
    }

    try {
      final allValues = await _secureStorage.readAll();
      for (final entry in allValues.entries) {
        if (_isWalletKey(entry.key)) {
          _secureValues[entry.key] = entry.value;
        }
      }

      _documentsDirectory = await getApplicationDocumentsDirectory();
      final temporaryDirectory = await getTemporaryDirectory();
      await temporaryDirectory.create(recursive: true);
      _snapshotDirectory = await temporaryDirectory.createTemp(
        'cardvault_import_snapshot_',
      );

      for (final name in _mediaDirectories) {
        final source = Directory('${_documentsDirectory!.path}/$name');
        if (await source.exists()) {
          await _copyDirectory(
            source,
            Directory('${_snapshotDirectory!.path}/$name'),
          );
        }
      }

      _captured = true;
    } catch (_) {
      await dispose();
      rethrow;
    }
  }

  Future<void> rollback() async {
    if (!_captured ||
        _documentsDirectory == null ||
        _snapshotDirectory == null) {
      throw StateError('Cannot roll back an uncaptured backup import');
    }

    final currentValues = await _secureStorage.readAll();
    for (final key in currentValues.keys.where(_isWalletKey)) {
      if (!_secureValues.containsKey(key)) {
        await _secureStorage.delete(key: key);
      }
    }
    for (final entry in _secureValues.entries) {
      await _secureStorage.write(key: entry.key, value: entry.value);
    }

    for (final name in _mediaDirectories) {
      final current = Directory('${_documentsDirectory!.path}/$name');
      if (await current.exists()) {
        await current.delete(recursive: true);
      }

      final snapshot = Directory('${_snapshotDirectory!.path}/$name');
      if (await snapshot.exists()) {
        await _copyDirectory(snapshot, current);
      }
    }
  }

  Future<void> dispose() async {
    final snapshot = _snapshotDirectory;
    _snapshotDirectory = null;
    if (snapshot != null && await snapshot.exists()) {
      await snapshot.delete(recursive: true);
    }
  }

  bool _isWalletKey(String key) {
    return key == _cardsListKey ||
        key == _groupsKey ||
        key.startsWith(_cardPrefix);
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      if (entity is Directory) {
        await _copyDirectory(entity, Directory('${destination.path}/$name'));
      } else if (entity is File) {
        await entity.copy('${destination.path}/$name');
      }
    }
  }
}

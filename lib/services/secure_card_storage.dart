import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/card_data.dart';
import '../models/card_group.dart';

import 'package:uuid/uuid.dart';

import 'backup_crypto.dart';
import 'backup_import_transaction.dart';
import 'card_attachment_storage.dart';
import 'card_background_storage.dart';
import 'card_group_storage.dart';
import 'encryption_service.dart';
import 'storage_path_guard.dart';
import 'app_log_service.dart';

/// How an imported backup is applied on top of what is already stored.
enum BackupImportMode {
  /// Keep the existing cards and add the ones from the backup.
  merge,

  /// Wipe the existing cards and groups first, so the device ends up with
  /// exactly what the backup contains.
  replace,
}

class SecureCardStorage {
  static final SecureCardStorage _instance = SecureCardStorage._internal();
  factory SecureCardStorage() => _instance;
  SecureCardStorage._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      // A transient keystore error must be surfaced to the caller. Letting the
      // plugin reset here can turn one failed read into an empty wallet.
      resetOnError: false,
    ),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _cardsListKey = 'saved_cards_list';
  static const String _cardPrefix = 'card_';
  static const String _groupsKey = 'card_groups';

  // Cards are stored as an index plus one secure-storage entry per card. Keep
  // reads and mutations on a single queue so a list load can never observe a
  // save/delete half way through its multi-key operation.
  Future<void> _operationTail = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() operation) async {
    final previous = _operationTail;
    final release = Completer<void>();
    _operationTail = release.future;

    await previous;
    try {
      return await operation();
    } finally {
      release.complete();
    }
  }

  Future<String> saveCard(CardData cardData) {
    final span = AppLogService.instance.startSpan('Storage', 'Save card');
    return _serialized(() async {
      try {
        final cardId = await _saveCardUnlocked(cardData);
        span.complete();
        return cardId;
      } catch (e, stackTrace) {
        span.fail(e, stackTrace);
        throw Exception('Failed to save card: $e');
      }
    });
  }

  Future<String> _saveCardUnlocked(CardData cardData) async {
    final String cardId = cardData.id ?? const Uuid().v4();
    requireSafeStorageIdentifier(cardId, label: 'card ID');
    final CardData cardToSave = cardData.copyWith(
      id: cardId,
      savedDate: cardData.savedDate ?? DateTime.now(),
    );

    await _secureStorage.write(
      key: '$_cardPrefix$cardId',
      value: jsonEncode(cardToSave.toJson()),
    );
    await _addCardIdToList(cardId);
    return cardId;
  }

  Future<void> updateCard(CardData cardData) {
    final span = AppLogService.instance.startSpan('Storage', 'Update card');
    if (cardData.id == null) {
      final error = Exception('Cannot update card without ID');
      span.fail(error, StackTrace.current);
      return Future<void>.error(error);
    }

    return _serialized(() async {
      try {
        await _writeCardUnlocked(cardData);
        span.complete();
      } catch (e, stackTrace) {
        span.fail(e, stackTrace);
        throw Exception('Failed to update card: $e');
      }
    });
  }

  /// Updates one aspect of the latest persisted card instead of writing a
  /// potentially stale full-record copy held by a background screen task.
  Future<CardData?> updateCardById(
    String cardId,
    CardData Function(CardData current) update,
  ) {
    final span = AppLogService.instance.startSpan(
      'Storage',
      'Update latest card state',
    );
    return _serialized(() async {
      try {
        final current = await _loadCard(cardId);
        if (current == null) {
          span.complete(details: {'found': false});
          return null;
        }

        final updated = update(current);
        if (updated.id != cardId) {
          throw StateError('A card update cannot change its ID');
        }
        await _writeCardUnlocked(updated);
        span.complete(details: {'found': true});
        return updated;
      } catch (e, stackTrace) {
        span.fail(e, stackTrace);
        throw Exception('Failed to update card: $e');
      }
    });
  }

  Future<void> _writeCardUnlocked(CardData cardData) {
    final cardId = cardData.id;
    if (cardId == null) {
      throw const FormatException('Cannot write a card without an ID');
    }
    requireSafeStorageIdentifier(cardId, label: 'card ID');
    return _secureStorage.write(
      key: '$_cardPrefix$cardId',
      value: jsonEncode(cardData.toJson()),
    );
  }

  Future<void> _addCardIdToList(String cardId) async {
    final List<String> cardIds = await _getCardIdsList();
    if (!cardIds.contains(cardId)) {
      cardIds.add(cardId);
      await _secureStorage.write(
        key: _cardsListKey,
        value: jsonEncode(cardIds),
      );
    }
  }

  Future<List<String>> _getCardIdsList() async {
    final String? cardsListJson = await _secureStorage.read(key: _cardsListKey);
    if (cardsListJson == null) {
      return [];
    }

    final decoded = jsonDecode(cardsListJson);
    if (decoded is! List<dynamic>) {
      throw const FormatException('Saved card index is not a list');
    }
    final cardIds = decoded.cast<String>();
    for (final cardId in cardIds) {
      requireSafeStorageIdentifier(cardId, label: 'card ID');
    }
    return cardIds;
  }

  Future<List<CardData>> loadCards() {
    final span = AppLogService.instance.startSpan('Storage', 'Load wallet');
    return _serialized(() async {
      try {
        final List<String> cardIds = await _getCardIdsList();
        final List<CardData> cards = [];

        for (final cardId in cardIds) {
          // Keep the platform read outside the parse recovery below. A secure
          // storage failure is not evidence that the card was deleted, and
          // returning a partial list would incorrectly replace the UI wallet.
          final String? cardJson = await _secureStorage.read(
            key: '$_cardPrefix$cardId',
          );
          if (cardJson == null) {
            throw StateError('Saved card $cardId is temporarily unavailable');
          }

          try {
            final Map<String, dynamic> cardMap = jsonDecode(cardJson);
            final CardData card = CardData.fromJson(cardMap);
            cards.add(card);
          } catch (e) {
            // A single malformed legacy record should not make every healthy
            // card inaccessible. Unlike platform read failures, this result is
            // deterministic and safe to isolate.
            AppLogService.instance.action(
              'Storage',
              'Skipped malformed saved card',
              details: {'errorType': e.runtimeType},
            );
          }
        }

        cards.sort((a, b) {
          if (a.savedDate == null && b.savedDate == null) return 0;
          if (a.savedDate == null) return 1;
          if (b.savedDate == null) return -1;
          return b.savedDate!.compareTo(a.savedDate!);
        });

        span.complete(details: {'cardCount': cards.length});
        return cards;
      } catch (e, stackTrace) {
        span.fail(e, stackTrace);
        throw Exception('Failed to load cards: $e');
      }
    });
  }

  Future<CardData?> loadCard(String cardId) {
    final span = AppLogService.instance.startSpan('Storage', 'Load card');
    return _serialized(() async {
      try {
        final card = await _loadCard(cardId);
        span.complete(details: {'found': card != null});
        return card;
      } catch (e, stackTrace) {
        span.fail(e, stackTrace);
        throw Exception('Failed to load card: $e');
      }
    });
  }

  Future<CardData?> _loadCard(String cardId) async {
    try {
      requireSafeStorageIdentifier(cardId, label: 'card ID');
      final String? cardJson = await _secureStorage.read(
        key: '$_cardPrefix$cardId',
      );
      if (cardJson == null) {
        return null;
      }

      final Map<String, dynamic> cardMap = jsonDecode(cardJson);
      return CardData.fromJson(cardMap);
    } catch (e) {
      throw Exception('Failed to load card: $e');
    }
  }

  Future<void> deleteCard(String cardId) {
    final span = AppLogService.instance.startSpan('Storage', 'Delete card');
    return _serialized(() async {
      try {
        requireSafeStorageIdentifier(cardId, label: 'card ID');
        await _secureStorage.delete(key: '$_cardPrefix$cardId');

        final List<String> cardIds = await _getCardIdsList();
        cardIds.remove(cardId);
        await _secureStorage.write(
          key: _cardsListKey,
          value: jsonEncode(cardIds),
        );

        await CardAttachmentStorage().deleteAllForCard(cardId);
        await CardBackgroundStorage().deleteAllForCard(cardId);
        span.complete();
      } catch (e, stackTrace) {
        span.fail(e, stackTrace);
        throw Exception('Failed to delete card: $e');
      }
    });
  }

  Future<void> deleteAllCards() {
    final span = AppLogService.instance.startSpan(
      'Storage',
      'Delete all cards',
    );
    return _serialized(() async {
      try {
        await _deleteAllCardsUnlocked();
        span.complete();
      } catch (e, stackTrace) {
        span.fail(e, stackTrace);
        throw Exception('Failed to delete all cards: $e');
      }
    });
  }

  Future<void> _deleteAllCardsUnlocked() async {
    final List<String> cardIds = await _getCardIdsList();

    for (final cardId in cardIds) {
      await _secureStorage.delete(key: '$_cardPrefix$cardId');
      await CardAttachmentStorage().deleteAllForCard(cardId);
      await CardBackgroundStorage().deleteAllForCard(cardId);
    }

    await _secureStorage.delete(key: _cardsListKey);
  }

  Future<int> getCardCount() {
    return _serialized(() async {
      final List<String> cardIds = await _getCardIdsList();
      return cardIds.length;
    });
  }

  /// Writes a self-contained, password-encrypted `.cwbak` bundle. With
  /// [includePhotos] the card photos travel with the backup, so a file shared
  /// offline restores everything on the other device.
  Future<String> exportBackup(
    String password, {
    bool includePhotos = true,
  }) async {
    final span = AppLogService.instance.startSpan(
      'Backup',
      'Export vault',
      details: {'includePhotos': includePhotos},
    );
    try {
      final cards = await loadCards();
      final groups = await CardGroupStorage().loadGroups();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final path = await _writeBundle(
        cards: cards,
        groups: groups,
        password: password,
        includePhotos: includePhotos,
        directory: await _backupDirectory(),
        fileName: 'cards_wallet_backup_$timestamp.cwbak',
      );
      span.complete(details: {'cardCount': cards.length});
      return path;
    } catch (e, stackTrace) {
      span.fail(e, stackTrace);
      throw Exception('Failed to export cards: $e');
    }
  }

  /// Writes a shareable `.cwbak` holding a single card with every detail, note
  /// and photo. It uses the same format as a full backup, so the recipient
  /// restores it through the normal import flow.
  Future<String> exportSingleCard(
    CardData card,
    String password, {
    bool includePhotos = true,
  }) async {
    final span = AppLogService.instance.startSpan(
      'Backup',
      'Export single card',
      details: {'includePhotos': includePhotos},
    );
    try {
      final allGroups = await CardGroupStorage().loadGroups();
      final groups = allGroups.where((g) => g.id == card.groupId).toList();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final path = await _writeBundle(
        cards: [card],
        groups: groups,
        password: password,
        includePhotos: includePhotos,
        directory: await getTemporaryDirectory(),
        fileName: 'cards_wallet_card_${card.lastFourDigits}_$timestamp.cwbak',
      );
      span.complete();
      return path;
    } catch (e, stackTrace) {
      span.fail(e, stackTrace);
      throw Exception('Failed to export card: $e');
    }
  }

  Future<String> _writeBundle({
    required List<CardData> cards,
    required List<CardGroup> groups,
    required String password,
    required bool includePhotos,
    required Directory directory,
    required String fileName,
  }) async {
    if (password.length < backupMinimumPasswordLength) {
      throw Exception(
        'Password must be at least $backupMinimumPasswordLength characters',
      );
    }

    final encryptionService = EncryptionService();
    final masterKeyBase64 = await encryptionService.getMasterKeyBase64();
    final salt = encryptionService.generateSalt();
    final exportedAt = DateTime.now().toIso8601String();

    final photos = includePhotos
        ? await _collectPhotos(cards)
        : <String, Uint8List>{};

    final resultMap = await compute(
      exportBackupBundleInIsolate,
      BackupBundleExportRequest(
        encryptedCards: cards.map((card) => card.toJson()).toList(),
        groups: groups.map((group) => group.toJson()).toList(),
        photos: photos,
        masterKeyBase64: masterKeyBase64,
        password: password,
        saltBase64: base64Encode(salt),
        exportedAt: exportedAt,
      ).toMap(),
    );
    final result = BackupExportResult.fromMap(resultMap);

    final encryptedBackup = {
      'version': backupBundleVersion,
      'exported_at': result.exportedAt,
      'salt': result.saltBase64,
      'kdf': result.kdfParameters,
      'encrypted_data': result.encryptedData,
    };

    await directory.create(recursive: true);
    final filePath = '${directory.path}/$fileName';
    await File(filePath).writeAsString(jsonEncode(encryptedBackup));

    return filePath;
  }

  /// Total size of stored photos, used to warn before a large export. Scoped to
  /// a single card when [cardId] is given.
  Future<int> getPhotosSizeInBytes({String? cardId}) async {
    try {
      if (cardId != null) {
        requireSafeStorageIdentifier(cardId, label: 'card ID');
      }
      final root = await getApplicationDocumentsDirectory();
      final dir = Directory(
        cardId == null
            ? '${root.path}/card_attachments'
            : '${root.path}/card_attachments/$cardId',
      );
      if (!await dir.exists()) return 0;

      int total = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (e) {
      return 0;
    }
  }

  Future<Map<String, Uint8List>> _collectPhotos(List<CardData> cards) async {
    final attachmentStorage = CardAttachmentStorage();
    final backgroundStorage = CardBackgroundStorage();
    final photos = <String, Uint8List>{};

    for (final card in cards) {
      if (card.id == null) continue;
      for (final attachmentId in card.attachmentIds) {
        final bytes = await attachmentStorage.loadBytes(card.id!, attachmentId);
        if (bytes == null) continue;
        photos['$backupPhotosDir/${card.id}/$attachmentId.jpg'] = bytes;
      }
      final backgroundBytes = await backgroundStorage.loadBytes(
        card.customBackgroundImagePath,
      );
      if (backgroundBytes != null) {
        photos['$backupPhotosDir/${card.id}/${CardBackgroundStorage.backupFileName}'] =
            backgroundBytes;
      }
    }

    return photos;
  }

  Future<Directory> _backupDirectory() async {
    if (Platform.isAndroid) {
      return Directory('/storage/emulated/0/Download/CardsWallet');
    }
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/CardsWallet');
  }

  /// Imports a `.cwbak` bundle (format 3.0, photos included) or a legacy
  /// `.json` backup (format 1.0/2.0). Returns the number of cards restored.
  ///
  /// With [BackupImportMode.replace] the existing cards and groups are wiped,
  /// but only once the backup has been decrypted, so a wrong password can never
  /// cost the user their data.
  Future<int> importBackup(
    String filePath,
    String password, {
    BackupImportMode mode = BackupImportMode.merge,
  }) async {
    final span = AppLogService.instance.startSpan(
      'Backup',
      'Import vault',
      details: {'mode': mode.name},
    );
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Backup file not found');
      }
      if (await file.length() > backupMaxFileBytes) {
        throw const FormatException(
          'Backup file exceeds the import size limit',
        );
      }

      final backupData =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final version = backupData['version'] as String?;

      if (version == backupBundleVersion) {
        final count = await _importBundle(backupData, password, mode);
        span.complete(details: {'cardCount': count, 'format': 'bundle'});
        return count;
      }
      final count = await _importLegacyJson(backupData, password, mode);
      span.complete(details: {'cardCount': count, 'format': 'legacy'});
      return count;
    } catch (e, stackTrace) {
      span.fail(e, stackTrace);
      throw Exception('Failed to import cards: $e');
    }
  }

  Future<int> _importBundle(
    Map<String, dynamic> backupData,
    String password,
    BackupImportMode mode,
  ) async {
    final saltBase64 = backupData['salt'] as String?;
    if (saltBase64 == null) {
      throw Exception('Backup file is missing salt');
    }
    final rawKdfParameters = backupData['kdf'];
    if (rawKdfParameters != null && rawKdfParameters is! Map) {
      throw const FormatException('Backup KDF metadata is invalid');
    }
    final kdfParameters = rawKdfParameters == null
        ? null
        : Map<String, dynamic>.from(rawKdfParameters);

    final Map<String, dynamic> decrypted;
    try {
      decrypted = await compute(
        decryptBackupBundleInIsolate,
        BackupDecryptRequest(
          encryptedData: backupData['encrypted_data'] as String,
          password: password,
          saltBase64: saltBase64,
          kdfParameters: kdfParameters,
        ).toMap(),
      );
    } catch (_) {
      throw Exception('Decryption failed: wrong password or corrupted backup');
    }

    final decodedManifest = jsonDecode(decrypted['manifest'] as String);
    if (decodedManifest is! Map<String, dynamic>) {
      throw const FormatException('Backup manifest is not an object');
    }
    final manifest = decodedManifest;
    final photos = Map<String, Uint8List>.from(decrypted['photos'] as Map);
    _validateBundleManifest(manifest, photos.length);
    final groups = (manifest['groups'] as List<dynamic>? ?? [])
        .map((e) => CardGroup.fromJson(e as Map<String, dynamic>))
        .toList();
    final cardsList = manifest['cards'] as List<dynamic>;
    final preparedCards = <_PreparedBundleCard>[];
    final sourceCardIds = <String>{};

    // Validate and re-encrypt every record before mutating the current wallet.
    // A malformed card therefore aborts the import instead of producing a
    // partial restore.
    for (final entry in cardsList) {
      final map = Map<String, dynamic>.from(entry as Map);
      final sourceCardId = map['id'];
      if (sourceCardId is! String) {
        throw const FormatException('Backup card is missing a valid card ID');
      }
      requireSafeStorageIdentifier(sourceCardId, label: 'card ID');
      if (!sourceCardIds.add(sourceCardId)) {
        throw const FormatException('Backup contains duplicate card IDs');
      }

      final sourceAttachmentIds = <String>[];
      final seenAttachmentIds = <String>{};
      for (final value in map['attachmentIds'] as List<dynamic>? ?? const []) {
        if (value is! String) {
          throw const FormatException(
            'Backup contains an invalid attachment ID',
          );
        }
        requireSafeStorageIdentifier(value, label: 'attachment ID');
        if (!seenAttachmentIds.add(value)) {
          throw const FormatException(
            'Backup contains duplicate attachment IDs',
          );
        }
        sourceAttachmentIds.add(value);
      }

      preparedCards.add(
        _PreparedBundleCard(
          card: await _cardFromPlaintextMap(map),
          sourceCardId: sourceCardId,
          attachmentIds: sourceAttachmentIds,
          hasCustomBackgroundImage: map['hasCustomBackgroundImage'] == true,
        ),
      );
    }

    return _commitImport(
      mode: mode,
      groups: groups,
      writeCards: () async {
        final attachmentStorage = CardAttachmentStorage();
        final backgroundStorage = CardBackgroundStorage();

        for (final prepared in preparedCards) {
          final cardId = await _saveCardUnlocked(prepared.card);
          final attachmentIds = <String>[];

          for (final attachmentId in prepared.attachmentIds) {
            final bytes =
                photos['$backupPhotosDir/${prepared.sourceCardId}/$attachmentId.jpg'];
            if (bytes == null) continue;
            attachmentIds.add(
              await attachmentStorage.saveAttachmentBytes(cardId, bytes),
            );
          }

          String? backgroundPath;
          if (prepared.hasCustomBackgroundImage) {
            final bytes =
                photos['$backupPhotosDir/${prepared.sourceCardId}/${CardBackgroundStorage.backupFileName}'];
            if (bytes != null) {
              backgroundPath = await backgroundStorage.saveBackgroundBytes(
                cardId,
                bytes,
              );
            }
          }

          if (attachmentIds.isNotEmpty || backgroundPath != null) {
            await _writeCardUnlocked(
              prepared.card.copyWith(
                id: cardId,
                attachmentIds: attachmentIds,
                customBackgroundImagePath: backgroundPath,
              ),
            );
          }
        }

        return preparedCards.length;
      },
    );
  }

  Future<int> _commitImport({
    required BackupImportMode mode,
    required List<CardGroup> groups,
    required Future<int> Function() writeCards,
  }) {
    return _serialized(() async {
      final transaction = BackupImportTransaction(_secureStorage);
      await transaction.capture();

      try {
        if (mode == BackupImportMode.replace) {
          await _deleteAllCardsUnlocked();
        }
        await _writeImportedGroupsUnlocked(groups, mode);
        return await writeCards();
      } catch (error, stackTrace) {
        try {
          await transaction.rollback();
        } catch (rollbackError) {
          Error.throwWithStackTrace(
            Exception(
              'Backup import failed and the previous wallet could not be '
              'fully restored: $rollbackError. Original error: $error',
            ),
            stackTrace,
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      } finally {
        await transaction.dispose();
      }
    });
  }

  Future<void> _writeImportedGroupsUnlocked(
    List<CardGroup> importedGroups,
    BackupImportMode mode,
  ) async {
    if (mode == BackupImportMode.replace) {
      if (importedGroups.isEmpty) {
        await _secureStorage.delete(key: _groupsKey);
      } else {
        await _secureStorage.write(
          key: _groupsKey,
          value: jsonEncode(
            importedGroups.map((group) => group.toJson()).toList(),
          ),
        );
      }
      return;
    }

    if (importedGroups.isEmpty) return;
    final existingJson = await _secureStorage.read(key: _groupsKey);
    final existingGroups = existingJson == null
        ? <CardGroup>[]
        : (jsonDecode(existingJson) as List<dynamic>)
              .map((entry) => CardGroup.fromJson(entry as Map<String, dynamic>))
              .toList();
    final existingIds = existingGroups.map((group) => group.id).toSet();
    for (final group in importedGroups) {
      if (existingIds.add(group.id)) existingGroups.add(group);
    }
    await _secureStorage.write(
      key: _groupsKey,
      value: jsonEncode(existingGroups.map((group) => group.toJson()).toList()),
    );
  }

  Future<CardData> _cardFromPlaintextMap(Map<String, dynamic> map) {
    return CardData.fromPlaintext(
      cardNumber: map['cardNumber'] as String,
      expiryDate: map['expiryDate'] as String,
      cardholderName: map['cardholderName'] as String?,
      cvv: map['cvv'] as String?,
      accountNumber: map['accountNumber'] as String?,
      ifscCode: map['ifscCode'] as String?,
      upiId: map['upiId'] as String?,
      cardType: map['cardType'] as String,
      id: map['id'] as String?,
      savedDate: map['savedDate'] != null
          ? DateTime.parse(map['savedDate'] as String)
          : null,
      readMethod: map['readMethod'] != null
          ? ReadMethod.values.firstWhere(
              (e) => e.name == map['readMethod'],
              orElse: () => ReadMethod.nfc,
            )
          : ReadMethod.nfc,
      cardCategory: map['cardCategory'] != null
          ? CardCategory.values.firstWhere(
              (e) => e.name == map['cardCategory'],
              orElse: () => CardCategory.credit,
            )
          : CardCategory.credit,
      bankId: map['bankId'] as String?,
      cardNickname: map['cardNickname'] as String?,
      designId: map['designId'] as String?,
      customGradientStartColor: (map['customGradientStartColor'] as num?)
          ?.toInt(),
      customGradientEndColor: (map['customGradientEndColor'] as num?)?.toInt(),
      customGradientAngle:
          (map['customGradientAngle'] as num?)?.toDouble() ?? 135,
      backgroundImageBlur:
          (map['backgroundImageBlur'] as num?)?.toDouble() ?? 0,
      notes: map['notes'] as String?,
      groupId: map['groupId'] as String?,
    );
  }

  void _validateBundleManifest(
    Map<String, dynamic> manifest,
    int extractedPhotoCount,
  ) {
    final cards = manifest['cards'];
    final groups = manifest['groups'];
    if (manifest['version'] != backupBundleVersion ||
        cards is! List<dynamic> ||
        groups is! List<dynamic>) {
      throw const FormatException('Backup manifest structure is invalid');
    }
    if (cards.length > backupMaxCards || groups.length > backupMaxGroups) {
      throw const FormatException('Backup manifest exceeds record limits');
    }
    if (manifest['cards_count'] != cards.length ||
        manifest['photos_count'] != extractedPhotoCount) {
      throw const FormatException('Backup manifest counts are inconsistent');
    }

    for (final entry in cards) {
      if (entry is! Map) {
        throw const FormatException('Backup contains an invalid card record');
      }
      final attachmentIds = entry['attachmentIds'];
      if (attachmentIds != null &&
          (attachmentIds is! List ||
              attachmentIds.length > backupMaxAttachmentsPerCard)) {
        throw const FormatException('Backup card has too many attachments');
      }
    }
  }

  Future<int> _importLegacyJson(
    Map<String, dynamic> backupData,
    String password,
    BackupImportMode mode,
  ) async {
    try {
      final version = backupData['version'] as String?;

      if (version != '2.0' && version != '1.0') {
        throw Exception('Unsupported backup version');
      }

      final encryptedData = backupData['encrypted_data'] as String;
      final encryptionService = EncryptionService();
      late final String decryptedJson;

      if (version == '2.0') {
        final saltBase64 = backupData['salt'] as String?;
        if (saltBase64 == null) {
          throw Exception('Backup file is missing salt');
        }
        try {
          decryptedJson = await compute(
            decryptBackupInIsolate,
            BackupDecryptRequest(
              encryptedData: encryptedData,
              password: password,
              saltBase64: saltBase64,
            ).toMap(),
          );
        } catch (_) {
          throw Exception(
            'Decryption failed: wrong password or corrupted backup',
          );
        }
      } else {
        decryptedJson = await encryptionService.decrypt(encryptedData);
      }

      final cardsData = jsonDecode(decryptedJson) as Map<String, dynamic>;
      final cardsList = cardsData['cards'] as List<dynamic>;
      final preparedCards = <CardData>[];
      for (final cardJson in cardsList) {
        final map = Map<String, dynamic>.from(cardJson as Map);
        final card = version == '2.0'
            ? await _cardFromPlaintextMap(map)
            : CardData.fromJson(map);
        if (card.id != null) {
          requireSafeStorageIdentifier(card.id!, label: 'card ID');
        }
        preparedCards.add(card);
      }

      return await _commitImport(
        mode: mode,
        groups: const [],
        writeCards: () async {
          for (final card in preparedCards) {
            await _saveCardUnlocked(card);
          }
          return preparedCards.length;
        },
      );
    } catch (e) {
      throw Exception('Failed to import cards: $e');
    }
  }

  Future<String?> getLastBackupDate() async {
    try {
      final directory = await _backupDirectory();

      if (!await directory.exists()) {
        return null;
      }

      final files = await directory.list().toList();

      final backupFiles = files
          .whereType<File>()
          .where((file) => file.path.contains('cards_wallet_backup_'))
          .toList();

      if (backupFiles.isEmpty) return null;

      backupFiles.sort((a, b) => b.path.compareTo(a.path));
      final lastBackup = backupFiles.first;

      final timestamp = lastBackup.path
          .split('cards_wallet_backup_')[1]
          .split('.')[0];

      final date = DateTime.fromMillisecondsSinceEpoch(int.parse(timestamp));
      return date.toIso8601String();
    } catch (e) {
      return null;
    }
  }
}

class _PreparedBundleCard {
  const _PreparedBundleCard({
    required this.card,
    required this.sourceCardId,
    required this.attachmentIds,
    required this.hasCustomBackgroundImage,
  });

  final CardData card;
  final String? sourceCardId;
  final List<String> attachmentIds;
  final bool hasCustomBackgroundImage;
}

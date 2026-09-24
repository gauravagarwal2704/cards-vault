import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cards_wallet/models/card_data.dart';
import 'package:cards_wallet/services/backup_crypto.dart';
import 'package:cards_wallet/services/card_attachment_storage.dart';
import 'package:cards_wallet/services/card_background_storage.dart';
import 'package:cards_wallet/services/encryption_service.dart';
import 'package:cards_wallet/services/secure_card_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// The platform interface is a transitive part of flutter_secure_storage. It is
// imported directly only so this test can replace the method-channel backend.
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

CardData _card(
  String id, {
  String nickname = 'Original',
  String type = 'Unknown',
}) {
  return CardData(
    encryptedCardNumber: 'encrypted-number',
    encryptedExpiryDate: 'encrypted-expiry',
    lastFourDigits: id.padLeft(4, '0').substring(0, 4),
    cardType: type,
    id: id,
    cardNickname: nickname,
    savedDate: DateTime.utc(2026, 1, 1),
  );
}

Map<String, String> _storedCards(Iterable<CardData> cards) {
  final list = cards.toList();
  return {
    'saved_cards_list': jsonEncode(list.map((card) => card.id).toList()),
    for (final card in list) 'card_${card.id}': jsonEncode(card.toJson()),
  };
}

class _ControlledSecureStoragePlatform
    extends TestFlutterSecureStoragePlatform {
  _ControlledSecureStoragePlatform(
    super.data, {
    this.failingReadKey,
    this.operationDelay = Duration.zero,
  });

  final String? failingReadKey;
  String? failingWriteKey;
  int writeFailuresRemaining = 0;
  final Duration operationDelay;
  int activeOperations = 0;
  int maxActiveOperations = 0;
  final Map<String, int> writeCounts = {};

  Future<T> _track<T>(FutureOr<T> Function() operation) async {
    activeOperations++;
    if (activeOperations > maxActiveOperations) {
      maxActiveOperations = activeOperations;
    }
    try {
      if (operationDelay > Duration.zero) {
        await Future<void>.delayed(operationDelay);
      }
      return await operation();
    } finally {
      activeOperations--;
    }
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) {
    return _track(() {
      if (key == failingReadKey) {
        throw PlatformException(code: 'keystore-unavailable');
      }
      return data[key];
    });
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) {
    writeCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
    return _track(() {
      if (key == failingWriteKey && writeFailuresRemaining > 0) {
        writeFailuresRemaining--;
        throw PlatformException(code: 'injected-write-failure');
      }
      data[key] = value;
    });
  }
}

class _TestPathProviderPlatform extends PathProviderPlatform {
  _TestPathProviderPlatform(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      '${root.path}/documents';

  @override
  Future<String?> getTemporaryPath() async => '${root.path}/temporary';
}

Future<File> _writeBundle({
  required Directory root,
  required List<Map<String, dynamic>> encryptedCards,
  required String masterKeyBase64,
  List<Map<String, dynamic>> groups = const [],
  String password = 'correct-password',
}) async {
  final exported = BackupExportResult.fromMap(
    exportBackupBundleInIsolate(
      BackupBundleExportRequest(
        encryptedCards: encryptedCards,
        groups: groups,
        photos: const {},
        masterKeyBase64: masterKeyBase64,
        password: password,
        saltBase64: base64Encode(List.filled(16, 9)),
        exportedAt: '2026-08-26T00:00:00.000Z',
      ).toMap(),
    ),
  );
  final file = File('${root.path}/import.cwbak');
  await file.writeAsString(
    jsonEncode({
      'version': backupBundleVersion,
      'exported_at': exported.exportedAt,
      'salt': exported.saltBase64,
      'kdf': exported.kdfParameters,
      'encrypted_data': exported.encryptedData,
    }),
  );
  return file;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalPlatform = FlutterSecureStoragePlatform.instance;
  final originalPathProvider = PathProviderPlatform.instance;
  late Directory testRoot;

  setUp(() async {
    testRoot = await Directory.systemTemp.createTemp(
      'cardvault_secure_storage_test_',
    );
    PathProviderPlatform.instance = _TestPathProviderPlatform(testRoot);
  });

  tearDown(() async {
    FlutterSecureStoragePlatform.instance = originalPlatform;
    PathProviderPlatform.instance = originalPathProvider;
    if (await testRoot.exists()) await testRoot.delete(recursive: true);
  });

  test(
    'a secure-storage read failure never becomes a partial card list',
    () async {
      final platform = _ControlledSecureStoragePlatform(
        _storedCards([_card('0001'), _card('0002')]),
        failingReadKey: 'card_0002',
      );
      FlutterSecureStoragePlatform.instance = platform;

      await expectLater(
        SecureCardStorage().loadCards(),
        throwsA(isA<Exception>()),
      );
    },
  );

  test('card snapshots and writes are serialized', () async {
    final platform = _ControlledSecureStoragePlatform(
      _storedCards([_card('0001')]),
      operationDelay: const Duration(milliseconds: 5),
    );
    FlutterSecureStoragePlatform.instance = platform;
    final storage = SecureCardStorage();

    await Future.wait([storage.loadCards(), storage.getCardCount()]);

    expect(platform.maxActiveOperations, 1);
  });

  test('targeted background repair preserves a concurrent edit', () async {
    final platform = _ControlledSecureStoragePlatform(
      _storedCards([_card('0001')]),
      operationDelay: const Duration(milliseconds: 2),
    );
    FlutterSecureStoragePlatform.instance = platform;
    final storage = SecureCardStorage();

    await Future.wait([
      storage.updateCard(_card('0001', nickname: 'Edited')),
      storage.updateCardById(
        '0001',
        (current) => current.copyWith(cardType: 'Visa'),
      ),
    ]);

    final stored = await storage.loadCard('0001');
    expect(stored?.cardNickname, 'Edited');
    expect(stored?.cardType, 'Visa');
  });

  test('concurrent encryption calls initialize only one master key', () async {
    final platform = _ControlledSecureStoragePlatform(
      {},
      operationDelay: const Duration(milliseconds: 5),
    );
    FlutterSecureStoragePlatform.instance = platform;
    final encryption = EncryptionService();
    await encryption.clearKey();

    final encrypted = await Future.wait([
      encryption.encrypt('first'),
      encryption.encrypt('second'),
      encryption.encrypt('third'),
    ]);

    expect(platform.writeCounts['encryption_master_key'], 1);
    expect(await encryption.decrypt(encrypted[0]), 'first');
    expect(await encryption.decrypt(encrypted[1]), 'second');
    expect(await encryption.decrypt(encrypted[2]), 'third');
  });

  test(
    'replace import restores cards, groups, and media after a commit failure',
    () async {
      final oldCard = _card('old-card', nickname: 'Keep me');
      final oldGroupJson = jsonEncode([
        {
          'id': 'old-group',
          'name': 'Existing group',
          'colorValue': null,
          'createdAt': '2026-01-01T00:00:00.000Z',
        },
      ]);
      final platform = _ControlledSecureStoragePlatform({
        ..._storedCards([oldCard]),
        'card_groups': oldGroupJson,
      });
      FlutterSecureStoragePlatform.instance = platform;

      final encryption = EncryptionService();
      await encryption.clearKey();
      final importedCard = await CardData.fromPlaintext(
        cardNumber: '4111111111111111',
        expiryDate: '12/30',
        cardType: 'Visa',
        id: 'new-card',
      );
      final backupFile = await _writeBundle(
        root: testRoot,
        encryptedCards: [importedCard.toJson()],
        masterKeyBase64: await encryption.getMasterKeyBase64(),
        groups: const [
          {
            'id': 'new-group',
            'name': 'Imported group',
            'colorValue': null,
            'createdAt': '2026-08-26T00:00:00.000Z',
          },
        ],
      );

      final oldAttachment = File(
        '${testRoot.path}/documents/card_attachments/old-card/old.enc',
      );
      await oldAttachment.create(recursive: true);
      await oldAttachment.writeAsString('encrypted attachment');
      final oldBackground = File(
        '${testRoot.path}/documents/card_backgrounds/old-card/background.img',
      );
      await oldBackground.create(recursive: true);
      await oldBackground.writeAsString('existing background');

      platform
        ..failingWriteKey = 'card_new-card'
        ..writeFailuresRemaining = 1;

      await expectLater(
        SecureCardStorage().importBackup(
          backupFile.path,
          'correct-password',
          mode: BackupImportMode.replace,
        ),
        throwsA(isA<Exception>()),
      );

      expect(jsonDecode(platform.data['saved_cards_list']!), ['old-card']);
      expect(platform.data['card_old-card'], jsonEncode(oldCard.toJson()));
      expect(platform.data.containsKey('card_new-card'), isFalse);
      expect(platform.data['card_groups'], oldGroupJson);
      expect(await oldAttachment.readAsString(), 'encrypted attachment');
      expect(await oldBackground.readAsString(), 'existing background');
    },
  );

  test(
    'a malformed bundle is rejected before existing data is changed',
    () async {
      final oldCard = _card('old-card', nickname: 'Keep me');
      final platform = _ControlledSecureStoragePlatform(
        _storedCards([oldCard]),
      );
      FlutterSecureStoragePlatform.instance = platform;

      final encryption = EncryptionService();
      await encryption.clearKey();
      final validCard = await CardData.fromPlaintext(
        cardNumber: '4111111111111111',
        expiryDate: '12/30',
        cardType: 'Visa',
        id: 'valid-card',
      );
      final malformedCard = Map<String, dynamic>.from(validCard.toJson())
        ..remove('cardType');
      final backupFile = await _writeBundle(
        root: testRoot,
        encryptedCards: [validCard.toJson(), malformedCard],
        masterKeyBase64: await encryption.getMasterKeyBase64(),
      );

      await expectLater(
        SecureCardStorage().importBackup(
          backupFile.path,
          'correct-password',
          mode: BackupImportMode.replace,
        ),
        throwsA(isA<Exception>()),
      );

      expect(jsonDecode(platform.data['saved_cards_list']!), ['old-card']);
      expect(platform.data['card_old-card'], jsonEncode(oldCard.toJson()));
      expect(platform.data.containsKey('card_valid-card'), isFalse);
    },
  );

  for (final unsafeCardId in ['../escaped', r'..\escaped', 'groups']) {
    test(
      'unsafe imported card ID "$unsafeCardId" is rejected before commit',
      () async {
        final oldCard = _card('old-card', nickname: 'Keep me');
        final platform = _ControlledSecureStoragePlatform(
          _storedCards([oldCard]),
        );
        FlutterSecureStoragePlatform.instance = platform;

        final encryption = EncryptionService();
        await encryption.clearKey();
        final importedCard = await CardData.fromPlaintext(
          cardNumber: '4111111111111111',
          expiryDate: '12/30',
          cardType: 'Visa',
          id: unsafeCardId,
        );
        final backupFile = await _writeBundle(
          root: testRoot,
          encryptedCards: [importedCard.toJson()],
          masterKeyBase64: await encryption.getMasterKeyBase64(),
        );

        await expectLater(
          SecureCardStorage().importBackup(
            backupFile.path,
            'correct-password',
            mode: BackupImportMode.replace,
          ),
          throwsA(isA<Exception>()),
        );

        expect(jsonDecode(platform.data['saved_cards_list']!), ['old-card']);
        expect(platform.data['card_old-card'], jsonEncode(oldCard.toJson()));
        expect(platform.data['card_groups'], isNull);
      },
    );
  }

  test('unsafe imported attachment ID is rejected before commit', () async {
    final oldCard = _card('old-card', nickname: 'Keep me');
    final platform = _ControlledSecureStoragePlatform(_storedCards([oldCard]));
    FlutterSecureStoragePlatform.instance = platform;

    final encryption = EncryptionService();
    await encryption.clearKey();
    final importedCard = await CardData.fromPlaintext(
      cardNumber: '4111111111111111',
      expiryDate: '12/30',
      cardType: 'Visa',
      id: 'safe-card',
      attachmentIds: const ['../../outside'],
    );
    final backupFile = await _writeBundle(
      root: testRoot,
      encryptedCards: [importedCard.toJson()],
      masterKeyBase64: await encryption.getMasterKeyBase64(),
    );

    await expectLater(
      SecureCardStorage().importBackup(
        backupFile.path,
        'correct-password',
        mode: BackupImportMode.replace,
      ),
      throwsA(isA<Exception>()),
    );

    expect(jsonDecode(platform.data['saved_cards_list']!), ['old-card']);
    expect(platform.data['card_old-card'], jsonEncode(oldCard.toJson()));
  });

  test(
    'media stores reject traversal identifiers and external files',
    () async {
      final externalFile = File('${testRoot.path}/external.img');
      await externalFile.writeAsBytes([1, 2, 3]);

      await expectLater(
        CardAttachmentStorage().saveAttachmentBytes(
          '../outside',
          Uint8List.fromList([1]),
        ),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        CardBackgroundStorage().saveBackgroundBytes(
          '../outside',
          Uint8List.fromList([1]),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        await CardBackgroundStorage().loadBytes(externalFile.path),
        isNull,
      );
    },
  );

  test('media stores reject a symlinked storage root', () async {
    final documents = Directory('${testRoot.path}/documents');
    final outside = Directory('${testRoot.path}/outside')..createSync();
    await documents.create(recursive: true);
    await Link('${documents.path}/card_backgrounds').create(outside.path);

    await expectLater(
      CardBackgroundStorage().saveBackgroundBytes(
        'safe-card',
        Uint8List.fromList([1]),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(await outside.list().isEmpty, isTrue);
  });

  test('oversized backup files are rejected before JSON parsing', () async {
    final backupFile = File('${testRoot.path}/oversized.cwbak');
    final handle = await backupFile.open(mode: FileMode.write);
    await handle.truncate(backupMaxFileBytes + 1);
    await handle.close();

    await expectLater(
      SecureCardStorage().importBackup(backupFile.path, 'password'),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('import size limit'),
        ),
      ),
    );
  });
}

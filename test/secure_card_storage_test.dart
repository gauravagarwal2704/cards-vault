import 'dart:async';
import 'dart:convert';

import 'package:cards_wallet/models/card_data.dart';
import 'package:cards_wallet/services/encryption_service.dart';
import 'package:cards_wallet/services/secure_card_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
// The platform interface is a transitive part of flutter_secure_storage. It is
// imported directly only so this test can replace the method-channel backend.
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

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
    return _track(() => data[key] = value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalPlatform = FlutterSecureStoragePlatform.instance;

  tearDown(() {
    FlutterSecureStoragePlatform.instance = originalPlatform;
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
}

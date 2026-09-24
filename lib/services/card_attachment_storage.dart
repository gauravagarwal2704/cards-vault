import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'encryption_service.dart';
import 'storage_path_guard.dart';
import 'app_log_service.dart';

class CardAttachmentStorage {
  static final CardAttachmentStorage _instance =
      CardAttachmentStorage._internal();
  factory CardAttachmentStorage() => _instance;
  CardAttachmentStorage._internal();

  final EncryptionService _encryption = EncryptionService();
  final _uuid = const Uuid();

  Future<Directory> _cardDir(String cardId) async {
    return containedCardStorageDirectory(
      'card_attachments',
      cardId,
      create: true,
    );
  }

  Future<String> saveAttachment(String cardId, File source) async {
    return saveAttachmentBytes(cardId, await source.readAsBytes());
  }

  Future<String> saveAttachmentBytes(String cardId, Uint8List bytes) async {
    return AppLogService.instance.trace(
      'Storage',
      'Save card attachment',
      () async {
        requireSafeStorageIdentifier(cardId, label: 'card ID');
        final attachmentId = _uuid.v4();
        final encrypted = await _encryption.encrypt(base64Encode(bytes));
        final file = File('${(await _cardDir(cardId)).path}/$attachmentId.enc');
        await file.writeAsString(encrypted);
        return attachmentId;
      },
      details: {'byteCount': bytes.length},
    );
  }

  Future<List<String>> saveAttachments(
    String cardId,
    List<File> sources,
  ) async {
    final ids = <String>[];
    for (final source in sources) {
      ids.add(await saveAttachment(cardId, source));
    }
    return ids;
  }

  Future<Uint8List?> loadBytes(String cardId, String attachmentId) async {
    try {
      requireSafeStorageIdentifier(attachmentId, label: 'attachment ID');
      final file = File('${(await _cardDir(cardId)).path}/$attachmentId.enc');
      if (!await file.exists()) return null;
      return await _encryption.decryptBase64Bytes(await file.readAsString());
    } catch (error, stackTrace) {
      AppLogService.instance.recordFailure(
        'Load card attachment',
        error,
        stackTrace,
        category: 'Failure/Storage',
      );
      return null;
    }
  }

  Future<void> deleteAttachment(String cardId, String attachmentId) async {
    await AppLogService.instance.trace(
      'Storage',
      'Delete card attachment',
      () async {
        requireSafeStorageIdentifier(attachmentId, label: 'attachment ID');
        final file = File('${(await _cardDir(cardId)).path}/$attachmentId.enc');
        if (await file.exists()) {
          await file.delete();
        }
      },
    );
  }

  Future<void> deleteAttachments(
    String cardId,
    Iterable<String> attachmentIds,
  ) async {
    final ids = attachmentIds.toList(growable: false);
    await AppLogService.instance.trace(
      'Storage',
      'Delete card attachments',
      () async {
        for (final id in ids) {
          await deleteAttachment(cardId, id);
        }
      },
      details: {'count': ids.length},
    );
  }

  Future<void> deleteAllForCard(String cardId) async {
    await AppLogService.instance.trace(
      'Storage',
      'Delete all card attachments',
      () async {
        final dir = await containedCardStorageDirectory(
          'card_attachments',
          cardId,
        );
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      },
    );
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'encryption_service.dart';

class CardAttachmentStorage {
  static final CardAttachmentStorage _instance =
      CardAttachmentStorage._internal();
  factory CardAttachmentStorage() => _instance;
  CardAttachmentStorage._internal();

  final EncryptionService _encryption = EncryptionService();
  final _uuid = const Uuid();

  Future<Directory> _cardDir(String cardId) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/card_attachments/$cardId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> saveAttachment(String cardId, File source) async {
    return saveAttachmentBytes(cardId, await source.readAsBytes());
  }

  Future<String> saveAttachmentBytes(String cardId, Uint8List bytes) async {
    final attachmentId = _uuid.v4();
    final encrypted = await _encryption.encrypt(base64Encode(bytes));
    final file = File('${(await _cardDir(cardId)).path}/$attachmentId.enc');
    await file.writeAsString(encrypted);
    return attachmentId;
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
      final file = File('${(await _cardDir(cardId)).path}/$attachmentId.enc');
      if (!await file.exists()) return null;
      return await _encryption.decryptBase64Bytes(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteAttachment(String cardId, String attachmentId) async {
    final file = File('${(await _cardDir(cardId)).path}/$attachmentId.enc');
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> deleteAttachments(
    String cardId,
    Iterable<String> attachmentIds,
  ) async {
    for (final id in attachmentIds) {
      await deleteAttachment(cardId, id);
    }
  }

  Future<void> deleteAllForCard(String cardId) async {
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/card_attachments/$cardId',
    );
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

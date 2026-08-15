import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:pointycastle/export.dart';

const int backupPbkdf2Iterations = 100000;

/// Current backup format. `3.0` is an encrypted zip bundle (`.cwbak`) that also
/// carries card photos; `1.0`/`2.0` were JSON-only and remain importable.
const String backupBundleVersion = '3.0';

/// Path inside the bundle that holds the card and group metadata.
const String backupManifestPath = 'manifest.json';

/// Directory inside the bundle that holds the decrypted photos.
const String backupPhotosDir = 'photos';

class BackupExportResult {
  final String saltBase64;
  final String encryptedData;
  final String exportedAt;

  const BackupExportResult({
    required this.saltBase64,
    required this.encryptedData,
    required this.exportedAt,
  });

  Map<String, dynamic> toMap() => {
        'saltBase64': saltBase64,
        'encryptedData': encryptedData,
        'exportedAt': exportedAt,
      };

  factory BackupExportResult.fromMap(Map<String, dynamic> map) {
    return BackupExportResult(
      saltBase64: map['saltBase64'] as String,
      encryptedData: map['encryptedData'] as String,
      exportedAt: map['exportedAt'] as String,
    );
  }
}

class BackupDecryptRequest {
  final String encryptedData;
  final String password;
  final String saltBase64;

  const BackupDecryptRequest({
    required this.encryptedData,
    required this.password,
    required this.saltBase64,
  });

  Map<String, dynamic> toMap() => {
        'encryptedData': encryptedData,
        'password': password,
        'saltBase64': saltBase64,
      };

  factory BackupDecryptRequest.fromMap(Map<String, dynamic> map) {
    return BackupDecryptRequest(
      encryptedData: map['encryptedData'] as String,
      password: map['password'] as String,
      saltBase64: map['saltBase64'] as String,
    );
  }
}

class BackupBundleExportRequest {
  final List<Map<String, dynamic>> encryptedCards;
  final List<Map<String, dynamic>> groups;

  /// Decrypted photo bytes keyed by their path inside the bundle.
  final Map<String, Uint8List> photos;
  final String masterKeyBase64;
  final String password;
  final String saltBase64;
  final String exportedAt;

  const BackupBundleExportRequest({
    required this.encryptedCards,
    required this.groups,
    required this.photos,
    required this.masterKeyBase64,
    required this.password,
    required this.saltBase64,
    required this.exportedAt,
  });

  Map<String, dynamic> toMap() => {
        'encryptedCards': encryptedCards,
        'groups': groups,
        'photos': photos,
        'masterKeyBase64': masterKeyBase64,
        'password': password,
        'saltBase64': saltBase64,
        'exportedAt': exportedAt,
      };

  factory BackupBundleExportRequest.fromMap(Map<String, dynamic> map) {
    return BackupBundleExportRequest(
      encryptedCards: (map['encryptedCards'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      groups: (map['groups'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      photos: Map<String, Uint8List>.from(map['photos'] as Map),
      masterKeyBase64: map['masterKeyBase64'] as String,
      password: map['password'] as String,
      saltBase64: map['saltBase64'] as String,
      exportedAt: map['exportedAt'] as String,
    );
  }
}

/// Runs entirely in a background isolate via [compute].
///
/// Builds a zip of `manifest.json` plus the decrypted photos and encrypts the
/// whole archive with a key derived from [BackupBundleExportRequest.password].
Map<String, dynamic> exportBackupBundleInIsolate(Map<String, dynamic> raw) {
  final request = BackupBundleExportRequest.fromMap(raw);
  final masterKey = encrypt_pkg.Key.fromBase64(request.masterKeyBase64);

  final plaintextCards = request.encryptedCards
      .map((card) => _toPlaintextCard(card, masterKey))
      .toList();

  final manifest = {
    'version': backupBundleVersion,
    'exported_at': request.exportedAt,
    'cards_count': plaintextCards.length,
    'photos_count': request.photos.length,
    'cards': plaintextCards,
    'groups': request.groups,
  };

  final archive = Archive();
  final manifestBytes = utf8.encode(jsonEncode(manifest));
  archive.addFile(
    ArchiveFile(backupManifestPath, manifestBytes.length, manifestBytes),
  );
  request.photos.forEach((path, bytes) {
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  });

  final zipBytes = ZipEncoder().encode(archive);
  if (zipBytes == null) {
    throw Exception('Failed to build backup archive');
  }

  final encryptedData = _passwordEncryptBytes(
    Uint8List.fromList(zipBytes),
    request.password,
    base64Decode(request.saltBase64),
  );

  return BackupExportResult(
    saltBase64: request.saltBase64,
    encryptedData: encryptedData,
    exportedAt: request.exportedAt,
  ).toMap();
}

/// Runs entirely in a background isolate via [compute]. Returns the manifest
/// JSON plus the raw photo bytes found in the bundle.
Map<String, dynamic> decryptBackupBundleInIsolate(Map<String, dynamic> raw) {
  final request = BackupDecryptRequest.fromMap(raw);
  final zipBytes = _passwordDecryptBytes(
    request.encryptedData,
    request.password,
    base64Decode(request.saltBase64),
  );

  final archive = ZipDecoder().decodeBytes(zipBytes);
  String? manifestJson;
  final photos = <String, Uint8List>{};

  for (final file in archive.files) {
    if (!file.isFile) continue;
    if (file.name == backupManifestPath) {
      manifestJson = utf8.decode(file.content as List<int>);
    } else if (file.name.startsWith('$backupPhotosDir/')) {
      photos[file.name] = Uint8List.fromList(file.content as List<int>);
    }
  }

  if (manifestJson == null) {
    throw Exception('Backup bundle is missing its manifest');
  }

  return {
    'manifest': manifestJson,
    'photos': photos,
  };
}

/// Runs entirely in a background isolate via [compute].
String decryptBackupInIsolate(Map<String, dynamic> raw) {
  final request = BackupDecryptRequest.fromMap(raw);
  return _passwordDecrypt(
    request.encryptedData,
    request.password,
    base64Decode(request.saltBase64),
  );
}

Map<String, dynamic> _toPlaintextCard(
  Map<String, dynamic> card,
  encrypt_pkg.Key masterKey,
) {
  return {
    'cardNumber': _aesGcmDecrypt(card['encryptedCardNumber'] as String, masterKey),
    'expiryDate': _aesGcmDecrypt(card['encryptedExpiryDate'] as String, masterKey),
    'cardholderName': _decryptField(card['encryptedCardholderName'] as String?, masterKey),
    'cvv': _decryptField(card['encryptedCvv'] as String?, masterKey),
    'accountNumber': _decryptField(card['encryptedAccountNumber'] as String?, masterKey),
    'ifscCode': _decryptField(card['encryptedIfscCode'] as String?, masterKey),
    'upiId': _decryptField(card['encryptedUpiId'] as String?, masterKey),
    'lastFourDigits': card['lastFourDigits'],
    'cardType': card['cardType'],
    'id': card['id'],
    'savedDate': card['savedDate'],
    'readMethod': card['readMethod'],
    'cardCategory': card['cardCategory'],
    'bankId': card['bankId'],
    'cardNickname': card['cardNickname'],
    'designId': card['designId'],
    'notes': card['notes'],
    'groupId': card['groupId'],
    'attachmentIds': card['attachmentIds'],
  };
}

String? _decryptField(String? ciphertext, encrypt_pkg.Key key) {
  if (ciphertext == null || ciphertext.isEmpty) return null;
  return _aesGcmDecrypt(ciphertext, key);
}

String _passwordEncryptBytes(Uint8List plaintext, String password, Uint8List salt) {
  final key = _deriveKeyFromPassword(password, salt);
  final iv = encrypt_pkg.IV.fromSecureRandom(16);
  final encrypter = encrypt_pkg.Encrypter(
    encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.gcm),
  );
  final encrypted = encrypter.encryptBytes(plaintext, iv: iv);
  return '${iv.base64}:${encrypted.base64}';
}

Uint8List _passwordDecryptBytes(String ciphertext, String password, Uint8List salt) {
  final key = _deriveKeyFromPassword(password, salt);
  final parts = ciphertext.split(':');
  if (parts.length != 2) {
    throw Exception('Invalid encrypted data format');
  }
  final iv = encrypt_pkg.IV.fromBase64(parts[0]);
  final encrypted = encrypt_pkg.Encrypted.fromBase64(parts[1]);
  final encrypter = encrypt_pkg.Encrypter(
    encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.gcm),
  );
  return Uint8List.fromList(encrypter.decryptBytes(encrypted, iv: iv));
}

String _passwordDecrypt(String ciphertext, String password, Uint8List salt) {
  final key = _deriveKeyFromPassword(password, salt);
  return _aesGcmDecrypt(ciphertext, key);
}

encrypt_pkg.Key _deriveKeyFromPassword(String password, Uint8List salt) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, backupPbkdf2Iterations, 32));
  final keyBytes = derivator.process(Uint8List.fromList(utf8.encode(password)));
  return encrypt_pkg.Key(keyBytes);
}

String _aesGcmDecrypt(String ciphertext, encrypt_pkg.Key key) {
  final parts = ciphertext.split(':');
  if (parts.length != 2) {
    throw Exception('Invalid encrypted data format');
  }
  final iv = encrypt_pkg.IV.fromBase64(parts[0]);
  final encrypted = encrypt_pkg.Encrypted.fromBase64(parts[1]);
  final encrypter = encrypt_pkg.Encrypter(
    encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.gcm),
  );
  return encrypter.decrypt(encrypted, iv: iv);
}

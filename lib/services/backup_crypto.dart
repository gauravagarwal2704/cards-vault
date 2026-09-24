import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:image/image.dart' as image_lib;
import 'package:pointycastle/export.dart';

/// Retained only to import CardVault backups created before KDF metadata was
/// added to the envelope.
const int backupPbkdf2Iterations = 100000;
const int backupMinimumPasswordLength = 12;
const String backupKdfAlgorithm = 'argon2id';
const int backupKdfVersion = 19; // Argon2 v1.3 / 0x13.
const int backupArgon2MemoryKiB = 64 * 1024;
const int backupArgon2Iterations = 3;
const int backupArgon2Parallelism = 4;
const int backupDerivedKeyLength = 32;
const Map<String, Object> backupCurrentKdfParameters = {
  'algorithm': backupKdfAlgorithm,
  'version': backupKdfVersion,
  'memory_kib': backupArgon2MemoryKiB,
  'iterations': backupArgon2Iterations,
  'parallelism': backupArgon2Parallelism,
  'key_length': backupDerivedKeyLength,
};
const int _mib = 1024 * 1024;

/// Resource budgets applied before an untrusted backup can allocate or
/// decompress an unbounded amount of memory.
const int backupMaxFileBytes = 96 * _mib;
const int backupMaxCompressedArchiveBytes = 64 * _mib;
const int backupMaxUncompressedArchiveBytes = 80 * _mib;
const int backupMaxManifestBytes = 2 * _mib;
const int backupMaxPhotoBytes = 8 * _mib;
const int backupMaxArchiveEntries = 256;
const int backupMaxPhotos = backupMaxArchiveEntries - 1;
const int backupMaxArchivePathDepth = 3;
const int backupMaxArchivePathLength = 512;
const int backupMaxCentralDirectoryBytes = 256 * 1024;
const int backupMaxImagePixels = 16 * 1000 * 1000;
const int backupMaxAnimatedImageFrames = 10;
const int backupMaxAnimatedImagePixels = 32 * 1000 * 1000;
const int backupMaxCards = 500;
const int backupMaxGroups = 250;
const int backupMaxAttachmentsPerCard = 5;
const int backupMaxEncryptedDataCharacters =
    ((backupMaxCompressedArchiveBytes + 64) * 4 ~/ 3) + 32;

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
  final Map<String, dynamic> kdfParameters;

  const BackupExportResult({
    required this.saltBase64,
    required this.encryptedData,
    required this.exportedAt,
    required this.kdfParameters,
  });

  Map<String, dynamic> toMap() => {
    'saltBase64': saltBase64,
    'encryptedData': encryptedData,
    'exportedAt': exportedAt,
    'kdfParameters': kdfParameters,
  };

  factory BackupExportResult.fromMap(Map<String, dynamic> map) {
    return BackupExportResult(
      saltBase64: map['saltBase64'] as String,
      encryptedData: map['encryptedData'] as String,
      exportedAt: map['exportedAt'] as String,
      kdfParameters: Map<String, dynamic>.from(map['kdfParameters'] as Map),
    );
  }
}

class BackupDecryptRequest {
  final String encryptedData;
  final String password;
  final String saltBase64;
  final Map<String, dynamic>? kdfParameters;

  const BackupDecryptRequest({
    required this.encryptedData,
    required this.password,
    required this.saltBase64,
    this.kdfParameters,
  });

  Map<String, dynamic> toMap() {
    return {
      'encryptedData': encryptedData,
      'password': password,
      'saltBase64': saltBase64,
      if (kdfParameters != null) 'kdfParameters': kdfParameters,
    };
  }

  factory BackupDecryptRequest.fromMap(Map<String, dynamic> map) {
    return BackupDecryptRequest(
      encryptedData: map['encryptedData'] as String,
      password: map['password'] as String,
      saltBase64: map['saltBase64'] as String,
      kdfParameters: map['kdfParameters'] == null
          ? null
          : Map<String, dynamic>.from(map['kdfParameters'] as Map),
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
  if (plaintextCards.length > backupMaxCards ||
      request.groups.length > backupMaxGroups) {
    throw const FormatException('Backup exceeds record limits');
  }
  for (final card in plaintextCards) {
    final attachmentIds = card['attachmentIds'];
    if (attachmentIds is List &&
        attachmentIds.length > backupMaxAttachmentsPerCard) {
      throw const FormatException('A card has too many backup attachments');
    }
  }

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
  _validateManifestAndPhotoBudgets(manifestBytes, request.photos);
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
  if (zipBytes.length > backupMaxCompressedArchiveBytes) {
    throw const FormatException('Backup archive exceeds the compressed limit');
  }

  final encryptedData = _passwordEncryptBytes(
    Uint8List.fromList(zipBytes),
    request.password,
    _decodeBackupSalt(request.saltBase64),
    kdfParameters: backupCurrentKdfParameters,
  );
  if (encryptedData.length > backupMaxEncryptedDataCharacters) {
    throw const FormatException('Encrypted backup exceeds the size limit');
  }

  return BackupExportResult(
    saltBase64: request.saltBase64,
    encryptedData: encryptedData,
    exportedAt: request.exportedAt,
    kdfParameters: Map<String, dynamic>.from(backupCurrentKdfParameters),
  ).toMap();
}

/// Runs entirely in a background isolate via [compute]. Returns the manifest
/// JSON plus the raw photo bytes found in the bundle.
Map<String, dynamic> decryptBackupBundleInIsolate(Map<String, dynamic> raw) {
  final request = BackupDecryptRequest.fromMap(raw);
  _validateEncryptedDataLength(request.encryptedData);
  final zipBytes = _passwordDecryptBytes(
    request.encryptedData,
    request.password,
    _decodeBackupSalt(request.saltBase64),
    kdfParameters: request.kdfParameters,
  );
  if (zipBytes.length > backupMaxCompressedArchiveBytes) {
    throw const FormatException('Backup archive exceeds the compressed limit');
  }

  final preflight = _preflightZip(zipBytes);
  final directory = ZipDirectory.read(InputStream(zipBytes));
  if (directory.fileHeaders.length != preflight.entryCount) {
    throw const FormatException('Backup archive entry count is inconsistent');
  }
  String? manifestJson;
  final photos = <String, Uint8List>{};
  final seenPaths = <String>{};
  var actualUncompressedBytes = 0;

  for (final header in directory.fileHeaders) {
    final path = _validateArchiveEntry(header);
    if (!seenPaths.add(path)) {
      throw const FormatException('Backup archive contains duplicate paths');
    }

    final declaredSize = header.uncompressedSize;
    if (declaredSize == null || declaredSize < 0) {
      throw const FormatException('Backup archive has an invalid entry size');
    }
    final typeLimit = path == backupManifestPath
        ? backupMaxManifestBytes
        : backupMaxPhotoBytes;
    final remainingTotal =
        backupMaxUncompressedArchiveBytes - actualUncompressedBytes;
    if (declaredSize > typeLimit ||
        declaredSize > remainingTotal ||
        actualUncompressedBytes + declaredSize >
            backupMaxUncompressedArchiveBytes) {
      throw const FormatException('Backup archive exceeds extraction limits');
    }

    final extractionLimit = typeLimit < remainingTotal
        ? typeLimit
        : remainingTotal;
    final bytes = _extractEntryBytes(header, extractionLimit);
    actualUncompressedBytes += bytes.length;
    if (actualUncompressedBytes > backupMaxUncompressedArchiveBytes) {
      throw const FormatException('Backup archive exceeds extraction limits');
    }

    if (path == backupManifestPath) {
      if (manifestJson != null) {
        throw const FormatException('Backup archive has multiple manifests');
      }
      manifestJson = utf8.decode(bytes);
    } else {
      _validateImageBudget(bytes);
      photos[path] = bytes;
    }
  }

  if (manifestJson == null) {
    throw Exception('Backup bundle is missing its manifest');
  }

  return {'manifest': manifestJson, 'photos': photos};
}

/// Runs entirely in a background isolate via [compute].
String decryptBackupInIsolate(Map<String, dynamic> raw) {
  final request = BackupDecryptRequest.fromMap(raw);
  _validateEncryptedDataLength(request.encryptedData);
  return _passwordDecrypt(
    request.encryptedData,
    request.password,
    _decodeBackupSalt(request.saltBase64),
  );
}

void _validateManifestAndPhotoBudgets(
  List<int> manifestBytes,
  Map<String, Uint8List> photos,
) {
  if (manifestBytes.length > backupMaxManifestBytes) {
    throw const FormatException('Backup manifest exceeds the size limit');
  }
  if (photos.length > backupMaxPhotos) {
    throw const FormatException('Backup contains too many photos');
  }

  var totalBytes = manifestBytes.length;
  for (final entry in photos.entries) {
    _validatePhotoPath(entry.key);
    if (entry.value.length > backupMaxPhotoBytes) {
      throw const FormatException('A backup photo exceeds the size limit');
    }
    totalBytes += entry.value.length;
    if (totalBytes > backupMaxUncompressedArchiveBytes) {
      throw const FormatException('Backup exceeds the uncompressed size limit');
    }
    _validateImageBudget(entry.value);
  }
}

_ZipPreflight _preflightZip(Uint8List bytes) {
  if (bytes.length < 22) {
    throw const FormatException('Backup archive is truncated');
  }

  const signature = 0x06054b50;
  final minimumPosition = bytes.length > 65557 ? bytes.length - 65557 : 0;
  for (
    var position = bytes.length - 22;
    position >= minimumPosition;
    position--
  ) {
    if (_readUint32Le(bytes, position) != signature) continue;
    final commentLength = _readUint16Le(bytes, position + 20);
    if (position + 22 + commentLength != bytes.length) continue;

    final diskNumber = _readUint16Le(bytes, position + 4);
    final centralDirectoryDisk = _readUint16Le(bytes, position + 6);
    final entriesOnDisk = _readUint16Le(bytes, position + 8);
    final entryCount = _readUint16Le(bytes, position + 10);
    final centralDirectorySize = _readUint32Le(bytes, position + 12);
    final centralDirectoryOffset = _readUint32Le(bytes, position + 16);

    if (diskNumber != 0 ||
        centralDirectoryDisk != 0 ||
        entriesOnDisk != entryCount) {
      throw const FormatException('Multi-disk backups are not supported');
    }
    if (entryCount == 0xffff ||
        centralDirectorySize == 0xffffffff ||
        centralDirectoryOffset == 0xffffffff) {
      throw const FormatException('Zip64 backups are not supported');
    }
    if (entryCount == 0 || entryCount > backupMaxArchiveEntries) {
      throw const FormatException('Backup archive has too many entries');
    }
    if (centralDirectorySize > backupMaxCentralDirectoryBytes ||
        centralDirectoryOffset + centralDirectorySize > position) {
      throw const FormatException('Backup central directory is invalid');
    }
    return _ZipPreflight(entryCount);
  }

  throw const FormatException('Backup archive directory was not found');
}

String _validateArchiveEntry(ZipFileHeader header) {
  final path = header.filename;
  _validateSupportedArchivePath(path);

  if ((header.generalPurposeBitFlag & 0x1) != 0) {
    throw const FormatException('Nested ZIP encryption is not supported');
  }
  if (header.compressionMethod != ArchiveFile.STORE &&
      header.compressionMethod != ArchiveFile.DEFLATE) {
    throw const FormatException('Unsupported backup compression method');
  }

  final compressedSize = header.compressedSize;
  if (compressedSize == null ||
      compressedSize < 0 ||
      compressedSize > backupMaxCompressedArchiveBytes) {
    throw const FormatException('Backup entry has an invalid compressed size');
  }

  // Unix file type bits: permit regular files and archives with no type bits,
  // but reject links/devices before their content can be touched.
  if (header.versionMadeBy >> 8 == 3) {
    final mode = (header.externalFileAttributes ?? 0) >> 16;
    final fileType = mode & 0xF000;
    if (fileType != 0 && fileType != 0x8000) {
      throw const FormatException('Backup archive contains a non-regular file');
    }
  }
  return path;
}

void _validateSupportedArchivePath(String path) {
  if (path.isEmpty ||
      path.length > backupMaxArchivePathLength ||
      path.startsWith('/') ||
      path.contains(r'\')) {
    throw const FormatException('Backup archive contains an unsafe path');
  }
  if (path == backupManifestPath) return;
  _validatePhotoPath(path);
}

void _validatePhotoPath(String path) {
  final segments = path.split('/');
  if (segments.length > backupMaxArchivePathDepth ||
      segments.length != 3 ||
      segments.first != backupPhotosDir ||
      segments.any(
        (segment) => segment.isEmpty || segment == '.' || segment == '..',
      )) {
    throw const FormatException('Backup photo path is invalid');
  }

  final safeSegment = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
  if (!safeSegment.hasMatch(segments[1])) {
    throw const FormatException('Backup photo card ID is invalid');
  }
  final fileName = segments[2];
  final validFileName =
      fileName == '__card_background__' ||
      (fileName.endsWith('.jpg') &&
          safeSegment.hasMatch(fileName.substring(0, fileName.length - 4)));
  if (!validFileName) {
    throw const FormatException('Backup photo filename is invalid');
  }
}

Uint8List _extractEntryBytes(ZipFileHeader header, int byteLimit) {
  final zipFile = header.file;
  final rawContent = zipFile?.rawContent;
  if (zipFile == null || rawContent == null) {
    throw const FormatException('Backup entry has no readable content');
  }

  final output = _LimitedOutputStream(byteLimit);
  if (header.compressionMethod == ArchiveFile.STORE) {
    if (header.compressedSize != header.uncompressedSize) {
      throw const FormatException('Stored backup entry sizes do not match');
    }
    output.writeInputStream(rawContent);
  } else {
    Inflate.stream(rawContent, output);
  }
  final bytes = output.takeBytes();
  if (bytes.length != header.uncompressedSize) {
    throw const FormatException('Backup entry size does not match its header');
  }
  if (header.crc32 == null || getCrc32(bytes) != header.crc32) {
    throw const FormatException('Backup entry checksum is invalid');
  }
  return bytes;
}

void _validateImageBudget(Uint8List bytes) {
  try {
    final decoder = image_lib.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0) {
      throw const FormatException('Backup photo is not a supported image');
    }

    final pixels = info.width * info.height;
    final frames = info.numFrames;
    if (pixels > backupMaxImagePixels ||
        frames <= 0 ||
        frames > backupMaxAnimatedImageFrames ||
        pixels * frames > backupMaxAnimatedImagePixels) {
      throw const FormatException('Backup photo exceeds image decode limits');
    }
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Backup photo is not a supported image');
  }
}

void _validateEncryptedDataLength(String encryptedData) {
  if (encryptedData.isEmpty ||
      encryptedData.length > backupMaxEncryptedDataCharacters) {
    throw const FormatException('Encrypted backup exceeds the size limit');
  }
}

Uint8List _decodeBackupSalt(String encodedSalt) {
  if (encodedSalt.length > 64) {
    throw const FormatException('Backup salt is invalid');
  }
  try {
    final salt = base64Decode(encodedSalt);
    if (salt.length != 16) {
      throw const FormatException('Backup salt is invalid');
    }
    return salt;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Backup salt is invalid');
  }
}

int _readUint16Le(Uint8List bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

int _readUint32Le(Uint8List bytes, int offset) {
  return _readUint16Le(bytes, offset) |
      (_readUint16Le(bytes, offset + 2) << 16);
}

class _ZipPreflight {
  const _ZipPreflight(this.entryCount);

  final int entryCount;
}

class _LimitedOutputStream extends OutputStream {
  _LimitedOutputStream(this.limit) : super();

  final int limit;

  Uint8List takeBytes() => Uint8List.fromList(getBytes());

  void _reserve(int count) {
    if (count < 0 || length + count > limit) {
      throw const FormatException('Backup entry exceeds its extraction limit');
    }
  }

  @override
  void flush() {}

  @override
  void writeByte(int value) {
    _reserve(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, [int? len]) {
    final count = len ?? bytes.length;
    _reserve(count);
    super.writeBytes(bytes, count);
  }

  @override
  void writeInputStream(InputStreamBase stream) {
    _reserve(stream.length);
    super.writeInputStream(stream);
  }
}

Map<String, dynamic> _toPlaintextCard(
  Map<String, dynamic> card,
  encrypt_pkg.Key masterKey,
) {
  return {
    'cardNumber': _aesGcmDecrypt(
      card['encryptedCardNumber'] as String,
      masterKey,
    ),
    'expiryDate': _aesGcmDecrypt(
      card['encryptedExpiryDate'] as String,
      masterKey,
    ),
    'cardholderName': _decryptField(
      card['encryptedCardholderName'] as String?,
      masterKey,
    ),
    'cvv': _decryptField(card['encryptedCvv'] as String?, masterKey),
    'accountNumber': _decryptField(
      card['encryptedAccountNumber'] as String?,
      masterKey,
    ),
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
    'customGradientStartColor': card['customGradientStartColor'],
    'customGradientEndColor': card['customGradientEndColor'],
    'customGradientAngle': card['customGradientAngle'],
    'hasCustomBackgroundImage': card['customBackgroundImagePath'] != null,
    'backgroundImageBlur': card['backgroundImageBlur'],
    'notes': card['notes'],
    'groupId': card['groupId'],
    'attachmentIds': card['attachmentIds'],
  };
}

String? _decryptField(String? ciphertext, encrypt_pkg.Key key) {
  if (ciphertext == null || ciphertext.isEmpty) return null;
  return _aesGcmDecrypt(ciphertext, key);
}

String _passwordEncryptBytes(
  Uint8List plaintext,
  String password,
  Uint8List salt, {
  required Map<String, dynamic> kdfParameters,
}) {
  final key = _deriveKeyFromPassword(password, salt, kdfParameters);
  final iv = encrypt_pkg.IV.fromSecureRandom(12);
  final encrypter = encrypt_pkg.Encrypter(
    encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.gcm),
  );
  final encrypted = encrypter.encryptBytes(plaintext, iv: iv);
  return '${iv.base64}:${encrypted.base64}';
}

Uint8List _passwordDecryptBytes(
  String ciphertext,
  String password,
  Uint8List salt, {
  Map<String, dynamic>? kdfParameters,
}) {
  final key = _deriveKeyFromPassword(password, salt, kdfParameters);
  final parts = ciphertext.split(':');
  if (parts.length != 2) {
    throw Exception('Invalid encrypted data format');
  }
  final iv = encrypt_pkg.IV.fromBase64(parts[0]);
  final encrypted = encrypt_pkg.Encrypted.fromBase64(parts[1]);
  final expectedIvLength = kdfParameters == null ? 16 : 12;
  if (iv.bytes.length != expectedIvLength || encrypted.bytes.length < 16) {
    throw const FormatException('Invalid encrypted data format');
  }
  final encrypter = encrypt_pkg.Encrypter(
    encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.gcm),
  );
  return Uint8List.fromList(encrypter.decryptBytes(encrypted, iv: iv));
}

String _passwordDecrypt(String ciphertext, String password, Uint8List salt) {
  final key = _deriveKeyFromPassword(password, salt, null);
  return _aesGcmDecrypt(ciphertext, key);
}

encrypt_pkg.Key _deriveKeyFromPassword(
  String password,
  Uint8List salt,
  Map<String, dynamic>? kdfParameters,
) {
  final passwordBytes = Uint8List.fromList(utf8.encode(password));
  try {
    if (kdfParameters == null) {
      final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(
          Pbkdf2Parameters(
            salt,
            backupPbkdf2Iterations,
            backupDerivedKeyLength,
          ),
        );
      return encrypt_pkg.Key(derivator.process(passwordBytes));
    }

    _validateCurrentKdfParameters(kdfParameters);
    final derivator = Argon2BytesGenerator()
      ..init(
        Argon2Parameters(
          Argon2Parameters.ARGON2_id,
          salt,
          desiredKeyLength: backupDerivedKeyLength,
          version: Argon2Parameters.ARGON2_VERSION_13,
          iterations: backupArgon2Iterations,
          memory: backupArgon2MemoryKiB,
          lanes: backupArgon2Parallelism,
        ),
      );
    return encrypt_pkg.Key(derivator.process(passwordBytes));
  } finally {
    passwordBytes.fillRange(0, passwordBytes.length, 0);
  }
}

void _validateCurrentKdfParameters(Map<String, dynamic> parameters) {
  for (final entry in backupCurrentKdfParameters.entries) {
    if (parameters[entry.key] != entry.value) {
      throw const FormatException('Unsupported backup KDF parameters');
    }
  }
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

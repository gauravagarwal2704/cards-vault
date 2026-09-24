import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cards_wallet/services/backup_crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

const _password = 'hunter2secret';
final _salt = Uint8List.fromList(List.filled(16, 3));
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

Map<String, dynamic> _decryptRequestForArchive(Archive archive) {
  return _decryptRequestForZipBytes(
    Uint8List.fromList(ZipEncoder().encode(archive)!),
  );
}

Map<String, dynamic> _decryptRequestForZipBytes(Uint8List zipBytes) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(_salt, backupPbkdf2Iterations, 32));
  final key = encrypt_pkg.Key(
    derivator.process(Uint8List.fromList(utf8.encode(_password))),
  );
  final iv = encrypt_pkg.IV.fromLength(16);
  final encrypted = encrypt_pkg.Encrypter(
    encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.gcm),
  ).encryptBytes(zipBytes, iv: iv);
  return BackupDecryptRequest(
    encryptedData: '${iv.base64}:${encrypted.base64}',
    password: _password,
    saltBase64: base64Encode(_salt),
  ).toMap();
}

void _understatePhotoSize(Uint8List zipBytes) {
  int readUint16Le(int offset) =>
      zipBytes[offset] | (zipBytes[offset + 1] << 8);
  int readUint32Le(int offset) =>
      readUint16Le(offset) | (readUint16Le(offset + 2) << 16);
  void writeOne(int offset) {
    zipBytes
      ..[offset] = 1
      ..[offset + 1] = 0
      ..[offset + 2] = 0
      ..[offset + 3] = 0;
  }

  for (var offset = 0; offset + 46 <= zipBytes.length; offset++) {
    final signature = readUint32Le(offset);
    int? nameOffset;
    int? nameLength;
    int? sizeOffset;
    if (signature == 0x04034b50 && offset + 30 <= zipBytes.length) {
      nameLength = readUint16Le(offset + 26);
      nameOffset = offset + 30;
      sizeOffset = offset + 22;
    } else if (signature == 0x02014b50) {
      nameLength = readUint16Le(offset + 28);
      nameOffset = offset + 46;
      sizeOffset = offset + 24;
    }
    if (nameOffset == null ||
        nameLength == null ||
        nameOffset + nameLength > zipBytes.length) {
      continue;
    }
    final name = utf8.decode(
      zipBytes.sublist(nameOffset, nameOffset + nameLength),
    );
    if (name.endsWith('/photo.jpg')) writeOne(sizeOffset!);
  }
}

Archive _archiveWithManifest() {
  final manifest = utf8.encode(
    jsonEncode({
      'version': backupBundleVersion,
      'cards_count': 0,
      'photos_count': 0,
      'cards': const [],
      'groups': const [],
    }),
  );
  return Archive()
    ..addFile(ArchiveFile(backupManifestPath, manifest.length, manifest));
}

Uint8List _oversizedPixelPng() {
  final bytes = BytesBuilder(copy: false);

  void writeUint32(int value) {
    bytes.add([
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ]);
  }

  bytes.add([137, 80, 78, 71, 13, 10, 26, 10]);
  final ihdr = <int>[
    ...ascii.encode('IHDR'),
    0,
    0,
    0x13,
    0x88, // 5000px
    0,
    0,
    0x0f,
    0xa0, // 4000px
    8,
    2,
    0,
    0,
    0,
  ];
  writeUint32(13);
  bytes.add(ihdr);
  writeUint32(getCrc32(ihdr));
  writeUint32(0);
  final iend = ascii.encode('IEND');
  bytes.add(iend);
  writeUint32(getCrc32(iend));
  return bytes.takeBytes();
}

void main() {
  test('bundle export/import round-trips manifest and photos', () {
    final photo = Uint8List.fromList(_onePixelPng);

    final exported = exportBackupBundleInIsolate(
      BackupBundleExportRequest(
        encryptedCards: const [],
        groups: const [
          {
            'id': 'g1',
            'name': 'Axis',
            'colorValue': null,
            'createdAt': '2026-01-01T00:00:00.000',
          },
        ],
        photos: {'$backupPhotosDir/card-1/att-1.jpg': photo},
        masterKeyBase64: base64Encode(List.filled(32, 7)),
        password: _password,
        saltBase64: base64Encode(List.filled(16, 3)),
        exportedAt: '2026-01-01T00:00:00.000',
      ).toMap(),
    );

    final result = BackupExportResult.fromMap(exported);
    expect(result.kdfParameters, backupCurrentKdfParameters);
    expect(base64Decode(result.encryptedData.split(':').first), hasLength(12));

    final decrypted = decryptBackupBundleInIsolate(
      BackupDecryptRequest(
        encryptedData: result.encryptedData,
        password: _password,
        saltBase64: result.saltBase64,
        kdfParameters: result.kdfParameters,
      ).toMap(),
    );

    final manifest =
        jsonDecode(decrypted['manifest'] as String) as Map<String, dynamic>;
    expect(manifest['version'], backupBundleVersion);
    expect((manifest['groups'] as List).single['name'], 'Axis');

    final photos = Map<String, Uint8List>.from(decrypted['photos'] as Map);
    expect(photos['$backupPhotosDir/card-1/att-1.jpg'], photo);
  });

  test('wrong password fails to decrypt', () {
    final exported = BackupExportResult.fromMap(
      exportBackupBundleInIsolate(
        BackupBundleExportRequest(
          encryptedCards: const [],
          groups: const [],
          photos: const {},
          masterKeyBase64: base64Encode(List.filled(32, 7)),
          password: 'correct-password',
          saltBase64: base64Encode(List.filled(16, 3)),
          exportedAt: '2026-01-01T00:00:00.000',
        ).toMap(),
      ),
    );

    expect(
      () => decryptBackupBundleInIsolate(
        BackupDecryptRequest(
          encryptedData: exported.encryptedData,
          password: 'wrong-password',
          saltBase64: exported.saltBase64,
          kdfParameters: exported.kdfParameters,
        ).toMap(),
      ),
      throwsA(anything),
    );

    final weakenedParameters = Map<String, dynamic>.from(exported.kdfParameters)
      ..['memory_kib'] = 1024;
    expect(
      () => decryptBackupBundleInIsolate(
        BackupDecryptRequest(
          encryptedData: exported.encryptedData,
          password: 'correct-password',
          saltBase64: exported.saltBase64,
          kdfParameters: weakenedParameters,
        ).toMap(),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('legacy PBKDF2 bundle remains importable without KDF metadata', () {
    final decrypted = decryptBackupBundleInIsolate(
      _decryptRequestForArchive(_archiveWithManifest()),
    );

    final manifest = jsonDecode(decrypted['manifest'] as String);
    expect(manifest['version'], backupBundleVersion);
  });

  test('rejects an archive with too many entries before extraction', () {
    final archive = _archiveWithManifest();
    for (var i = 0; i < backupMaxArchiveEntries; i++) {
      archive.addFile(
        ArchiveFile(
          '$backupPhotosDir/card-$i/photo.jpg',
          _onePixelPng.length,
          _onePixelPng,
        ),
      );
    }

    expect(
      () => decryptBackupBundleInIsolate(_decryptRequestForArchive(archive)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects nested archive paths before extraction', () {
    final archive = _archiveWithManifest()
      ..addFile(
        ArchiveFile(
          '$backupPhotosDir/card/deep/photo.jpg',
          _onePixelPng.length,
          _onePixelPng,
        ),
      );

    expect(
      () => decryptBackupBundleInIsolate(_decryptRequestForArchive(archive)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects photos whose decoded pixel budget is excessive', () {
    final oversized = _oversizedPixelPng();
    final archive = _archiveWithManifest()
      ..addFile(
        ArchiveFile(
          '$backupPhotosDir/card/photo.jpg',
          oversized.length,
          oversized,
        ),
      );

    expect(
      () => decryptBackupBundleInIsolate(_decryptRequestForArchive(archive)),
      throwsA(isA<FormatException>()),
    );
  });

  test('bounds decompression when entry metadata understates output', () {
    final oversized = Uint8List(backupMaxPhotoBytes + 1);
    final archive = _archiveWithManifest()
      ..addFile(
        ArchiveFile(
          '$backupPhotosDir/card/photo.jpg',
          oversized.length,
          oversized,
        ),
      );
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
    _understatePhotoSize(zipBytes);

    expect(
      () => decryptBackupBundleInIsolate(_decryptRequestForZipBytes(zipBytes)),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('extraction limit'),
        ),
      ),
    );
  });
}

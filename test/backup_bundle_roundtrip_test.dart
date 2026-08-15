import 'dart:convert';
import 'dart:typed_data';

import 'package:cards_wallet/services/backup_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundle export/import round-trips manifest and photos', () {
    final photo = Uint8List.fromList(List.generate(2048, (i) => i % 256));

    final exported = exportBackupBundleInIsolate(
      BackupBundleExportRequest(
        encryptedCards: const [],
        groups: const [
          {'id': 'g1', 'name': 'Axis', 'colorValue': null, 'createdAt': '2026-01-01T00:00:00.000'},
        ],
        photos: {'$backupPhotosDir/card-1/att-1.jpg': photo},
        masterKeyBase64: base64Encode(List.filled(32, 7)),
        password: 'hunter2secret',
        saltBase64: base64Encode(List.filled(16, 3)),
        exportedAt: '2026-01-01T00:00:00.000',
      ).toMap(),
    );

    final result = BackupExportResult.fromMap(exported);

    final decrypted = decryptBackupBundleInIsolate(
      BackupDecryptRequest(
        encryptedData: result.encryptedData,
        password: 'hunter2secret',
        saltBase64: result.saltBase64,
      ).toMap(),
    );

    final manifest = jsonDecode(decrypted['manifest'] as String) as Map<String, dynamic>;
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
        ).toMap(),
      ),
      throwsA(anything),
    );
  });
}

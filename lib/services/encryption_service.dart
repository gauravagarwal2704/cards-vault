import 'dart:convert';
import 'dart:math';

import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _keyStorageKey = 'encryption_master_key';
  encrypt_pkg.Key? _cachedKey;
  Future<encrypt_pkg.Key>? _keyInitialization;

  Future<encrypt_pkg.Key> _getOrCreateKey() async {
    if (_cachedKey != null) {
      return _cachedKey!;
    }

    final pending = _keyInitialization;
    if (pending != null) return pending;

    final initialization = _loadOrCreateKey();
    _keyInitialization = initialization;
    try {
      final key = await initialization;
      _cachedKey = key;
      return key;
    } catch (_) {
      // A later call may retry a transient secure-storage failure.
      if (identical(_keyInitialization, initialization)) {
        _keyInitialization = null;
      }
      rethrow;
    }
  }

  Future<encrypt_pkg.Key> _loadOrCreateKey() async {
    final storedKey = await _secureStorage.read(key: _keyStorageKey);
    if (storedKey != null) return encrypt_pkg.Key.fromBase64(storedKey);

    final key = encrypt_pkg.Key.fromSecureRandom(32);
    await _secureStorage.write(key: _keyStorageKey, value: key.base64);
    return key;
  }

  Future<String> getMasterKeyBase64() async {
    final key = await _getOrCreateKey();
    return key.base64;
  }

  Future<String> encrypt(String plaintext) async {
    try {
      if (plaintext.isEmpty) {
        return '';
      }

      final key = await _getOrCreateKey();
      return _aesGcmEncrypt(plaintext, key);
    } catch (e) {
      throw Exception('Encryption failed: $e');
    }
  }

  Future<String> decrypt(String ciphertext) async {
    try {
      if (ciphertext.isEmpty) {
        return '';
      }

      final key = await _getOrCreateKey();
      return _aesGcmDecrypt(ciphertext, key);
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
  }

  /// Decrypts an encrypted Base64 payload away from the UI isolate.
  ///
  /// Card attachments are much larger than the short text fields handled by
  /// [decrypt]. AES-GCM decryption and Base64 decoding them on the UI isolate
  /// can otherwise interrupt route and Hero animations.
  Future<Uint8List> decryptBase64Bytes(String ciphertext) async {
    try {
      if (ciphertext.isEmpty) return Uint8List(0);

      final key = await _getOrCreateKey();
      return await compute(_decryptBase64BytesInIsolate, {
        'ciphertext': ciphertext,
        'key': key.base64,
      });
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
  }

  Uint8List generateSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
  }

  String _aesGcmEncrypt(String plaintext, encrypt_pkg.Key key) {
    final iv = encrypt_pkg.IV.fromSecureRandom(16);
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.gcm),
    );
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
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

  String hashPin(String pin) {
    final bytes = utf8.encode(pin);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> clearKey() async {
    final pending = _keyInitialization;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // The key is being cleared anyway.
      }
    }
    _cachedKey = null;
    _keyInitialization = null;
    await _secureStorage.delete(key: _keyStorageKey);
  }
}

Uint8List _decryptBase64BytesInIsolate(Map<String, String> request) {
  final parts = request['ciphertext']!.split(':');
  if (parts.length != 2) {
    throw Exception('Invalid encrypted data format');
  }

  final key = encrypt_pkg.Key.fromBase64(request['key']!);
  final iv = encrypt_pkg.IV.fromBase64(parts[0]);
  final encrypted = encrypt_pkg.Encrypted.fromBase64(parts[1]);
  final encrypter = encrypt_pkg.Encrypter(
    encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.gcm),
  );
  final base64Payload = encrypter.decrypt(encrypted, iv: iv);
  return base64Decode(base64Payload);
}

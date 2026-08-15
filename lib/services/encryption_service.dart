import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static const String _keyStorageKey = 'encryption_master_key';
  encrypt_pkg.Key? _cachedKey;

  Future<encrypt_pkg.Key> _getOrCreateKey() async {
    if (_cachedKey != null) {
      return _cachedKey!;
    }

    String? storedKey = await _secureStorage.read(key: _keyStorageKey);
    
    if (storedKey != null) {
      _cachedKey = encrypt_pkg.Key.fromBase64(storedKey);
      return _cachedKey!;
    }

    final key = encrypt_pkg.Key.fromSecureRandom(32);
    await _secureStorage.write(
      key: _keyStorageKey,
      value: key.base64,
    );
    
    _cachedKey = key;
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
    _cachedKey = null;
    await _secureStorage.delete(key: _keyStorageKey);
  }
}

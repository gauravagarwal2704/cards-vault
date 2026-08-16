import 'dart:convert';
import 'dart:io';

import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_scan_settings_service.dart';

class AiScanLogEntry {
  final String id;
  final DateTime createdAt;
  final AiScanProvider provider;
  final String model;
  final String endpoint;
  final int? httpStatus;
  final bool succeeded;
  final String message;
  final String requestSummary;
  final String requestBody;
  final String responseBody;
  final String? validationSummary;

  const AiScanLogEntry({
    required this.id,
    required this.createdAt,
    required this.provider,
    required this.model,
    required this.endpoint,
    required this.httpStatus,
    required this.succeeded,
    required this.message,
    required this.requestSummary,
    required this.requestBody,
    required this.responseBody,
    this.validationSummary,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'created_at': createdAt.toUtc().toIso8601String(),
    'provider': provider.name,
    'model': model,
    'endpoint': endpoint,
    'http_status': httpStatus,
    'succeeded': succeeded,
    'message': message,
    'request_summary': requestSummary,
    'request_body': requestBody,
    'response_body': responseBody,
    'validation_summary': validationSummary,
  };

  factory AiScanLogEntry.fromJson(Map<String, dynamic> json) {
    final providerName = json['provider'] as String?;
    final provider = AiScanProvider.values.firstWhere(
      (value) => value.name == providerName,
      orElse: () => AiScanProvider.gemini,
    );
    return AiScanLogEntry(
      id: json['id'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      provider: provider,
      model: json['model'] as String? ?? provider.modelLabel,
      endpoint: json['endpoint'] as String? ?? '',
      httpStatus: (json['http_status'] as num?)?.toInt(),
      succeeded: json['succeeded'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      requestSummary: json['request_summary'] as String? ?? '',
      requestBody: json['request_body'] as String? ?? '',
      responseBody: json['response_body'] as String? ?? '',
      validationSummary: json['validation_summary'] as String?,
    );
  }
}

/// Keeps a small encrypted, device-local diagnostic history.
///
/// Image bytes and API keys are never logged. The encryption key lives in
/// platform secure storage and the encrypted payload is capped to the newest
/// [maximumEntries] attempts.
class AiScanLogService {
  static const maximumEntries = 10;
  static const _loggingEnabledKey = 'ai_scan_diagnostic_history_enabled';
  static const _encryptionKeyName = 'ai_scan_log_encryption_key_v1';
  static const _fileName = 'smart_scan_history_v1.enc';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: 'cardvault_ai_credentials',
      preferencesKeyPrefix: 'cardvault_ai_',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
      accountName: 'CardVault Smart Scan',
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
      accountName: 'CardVault Smart Scan',
      useDataProtectionKeyChain: true,
    ),
  );

  Future<bool> isLoggingEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_loggingEnabledKey) ?? true;
  }

  Future<void> setLoggingEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_loggingEnabledKey, enabled);
  }

  Future<List<AiScanLogEntry>> load() async {
    try {
      final file = await _logFile();
      if (!await file.exists()) return const [];
      final encrypted = await file.readAsString();
      final plaintext = await _decrypt(encrypted);
      final decoded = jsonDecode(plaintext);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (entry) =>
                AiScanLogEntry.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList();
    } catch (_) {
      // A corrupt or key-inaccessible log must never block scanning.
      return const [];
    }
  }

  Future<void> append(AiScanLogEntry entry) async {
    if (!await isLoggingEnabled()) return;
    final entries = await load();
    final retained = [entry, ...entries].take(maximumEntries).toList();
    final plaintext = jsonEncode(
      retained.map((item) => item.toJson()).toList(),
    );
    final encrypted = await _encrypt(plaintext);
    final file = await _logFile();
    await file.writeAsString(encrypted, flush: true);
  }

  Future<void> clear() async {
    final file = await _logFile();
    if (await file.exists()) await file.delete();
  }

  Future<File> _logFile() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/private_diagnostics');
    if (!await directory.exists()) await directory.create(recursive: true);
    return File('${directory.path}/$_fileName');
  }

  Future<encrypt_pkg.Key> _key() async {
    final stored = await _secureStorage.read(key: _encryptionKeyName);
    if (stored != null && stored.isNotEmpty) {
      return encrypt_pkg.Key.fromBase64(stored);
    }
    final key = encrypt_pkg.Key.fromSecureRandom(32);
    await _secureStorage.write(key: _encryptionKeyName, value: key.base64);
    return key;
  }

  Future<String> _encrypt(String plaintext) async {
    final iv = encrypt_pkg.IV.fromSecureRandom(16);
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(await _key(), mode: encrypt_pkg.AESMode.gcm),
    );
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  Future<String> _decrypt(String ciphertext) async {
    final parts = ciphertext.split(':');
    if (parts.length != 2) throw const FormatException('Invalid log data');
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(await _key(), mode: encrypt_pkg.AESMode.gcm),
    );
    return encrypter.decrypt(
      encrypt_pkg.Encrypted.fromBase64(parts[1]),
      iv: encrypt_pkg.IV.fromBase64(parts[0]),
    );
  }
}

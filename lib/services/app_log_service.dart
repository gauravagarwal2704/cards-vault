import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps a bounded, redacted record of recent app diagnostics for support.
///
/// Logs are encrypted at rest and bounded by age, entry count, and total size.
/// User-initiated exports are written to the app's temporary directory and
/// contain no card data by design.
class AppLogService {
  AppLogService._({DiagnosticLogStore? store})
    : _store = store ?? EncryptedDiagnosticLogStore();

  static final AppLogService instance = AppLogService._();

  // Keep enough history for a normal troubleshooting session while preventing
  // diagnostic storage from growing without bound.
  static const int _maximumEntries = 2000;
  static const int _maximumEntryLength = 4000;
  static const int _maximumPlaintextBytes = 1024 * 1024;
  static const Duration _retention = Duration(hours: 72);
  static const Duration _persistDebounce = Duration(milliseconds: 250);
  static const MethodChannel _nativeDiagnosticsChannel = MethodChannel(
    'cards_wallet/diagnostics',
  );

  final List<String> _entries = <String>[];
  final DiagnosticLogStore _store;
  DebugPrintCallback? _originalDebugPrint;
  FlutterExceptionHandler? _originalFlutterErrorHandler;
  ErrorCallback? _originalPlatformErrorHandler;
  bool _isCapturing = false;
  int _discardedEntryCount = 0;
  int _sequence = 0;
  bool _restoreComplete = false;
  bool _restoreStarted = false;
  bool _persistenceFailureReported = false;
  Timer? _persistTimer;
  Future<void> _restoreFuture = Future<void>.value();
  Future<void> _persistenceTail = Future<void>.value();
  final String _sessionId = DateTime.now()
      .toUtc()
      .microsecondsSinceEpoch
      .toRadixString(36);

  @visibleForTesting
  factory AppLogService.forTesting(DiagnosticLogStore store) =>
      AppLogService._(store: store);

  void startCapture() {
    if (_isCapturing) return;
    _isCapturing = true;
    unawaited(initializePersistence());
    _nativeDiagnosticsChannel.setMethodCallHandler(_handleNativeDiagnostic);

    _originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      _originalDebugPrint?.call(message, wrapWidth: wrapWidth);
      if (message != null) record('Flutter', message);
    };

    _originalFlutterErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      recordFailure(
        'Flutter framework',
        details.exception,
        details.stack ?? StackTrace.empty,
        fatal: true,
      );
      _originalFlutterErrorHandler?.call(details);
    };

    _originalPlatformErrorHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      recordFailure('Uncaught platform error', error, stack, fatal: true);
      return _originalPlatformErrorHandler?.call(error, stack) ?? false;
    };

    record('Lifecycle', 'CardVault diagnostic capture started');
  }

  Future<void> initializePersistence() {
    if (!_restoreStarted) {
      _restoreStarted = true;
      _restoreFuture = _restorePersistedLogs();
    }
    return _restoreFuture;
  }

  void record(String category, String message) {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    var sanitized = sanitize(message);
    if (sanitized.length > _maximumEntryLength) {
      sanitized = '${sanitized.substring(0, _maximumEntryLength)}…';
    }
    _entries.add(
      '[$timestamp] [session=$_sessionId #${++_sequence}] [$category] $sanitized',
    );
    if (_entries.length > _maximumEntries) {
      final overflow = _entries.length - _maximumEntries;
      _entries.removeRange(0, overflow);
      _discardedEntryCount += overflow;
    }
    _schedulePersist();
  }

  void recordFailure(
    String operation,
    Object error,
    StackTrace stackTrace, {
    String category = 'Failure',
    bool fatal = false,
  }) {
    record(
      fatal ? 'Crash/$category' : category,
      '$operation failed | errorType=${error.runtimeType} | error=$error\n'
      'stackTrace=$stackTrace',
    );
    if (fatal) unawaited(flush());
  }

  AppLogSpan startSpan(
    String area,
    String operation, {
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    action(area, '$operation started', details: details);
    return AppLogSpan._(this, area, operation, Stopwatch()..start());
  }

  Future<T> trace<T>(
    String area,
    String operation,
    Future<T> Function() callback, {
    Map<String, Object?> details = const <String, Object?>{},
  }) async {
    final span = startSpan(area, operation, details: details);
    try {
      final result = await callback();
      span.complete();
      return result;
    } catch (error, stackTrace) {
      span.fail(error, stackTrace);
      rethrow;
    }
  }

  /// Records a user-visible action without accepting arbitrary model data.
  ///
  /// Call sites must use non-sensitive values only (counts, booleans, enum
  /// names, and generic field names). Card numbers, cardholder names, notes,
  /// account identifiers, and stable card IDs must never be passed here.
  void action(
    String area,
    String action, {
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    final metadata = details.entries
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key}=${entry.value}')
        .join(', ');
    record('Action/$area', metadata.isEmpty ? action : '$action ($metadata)');
  }

  @visibleForTesting
  static String sanitize(String value) {
    var result = value;
    result = result.replaceAll(
      RegExp(
        r'\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b',
        caseSensitive: false,
      ),
      '[REDACTED_INTERNAL_ID]',
    );
    result = result.replaceAll(
      RegExp(r'\b(?:\d[ -]?){12,19}\b'),
      '[REDACTED_CARD_NUMBER]',
    );
    result = result.replaceAll(
      RegExp(r'\b(?:0[1-9]|1[0-2])[/ -]\d{2,4}\b'),
      '[REDACTED_EXPIRY]',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'\b(cvv|cvc|security code)\s*[:=]?\s*\d{3,4}\b',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)} [REDACTED]',
    );
    result = result.replaceAll(
      RegExp(r'\bsk-[A-Za-z0-9_-]+\b', caseSensitive: false),
      '[REDACTED_API_KEY]',
    );
    result = result.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9._~-]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    result = result.replaceAllMapped(
      RegExp(r'([?&][^=\s]+)=([^&\s]+)'),
      (match) => '${match.group(1)}=[REDACTED]',
    );
    result = result.replaceAll(
      RegExp(r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\b', caseSensitive: false),
      '[REDACTED_ACCOUNT_ID]',
    );
    result = result.replaceAll(
      RegExp(r'(?:[A-Za-z]:\\|/)(?:[^\s:]+[\\/])+[^\s:]+'),
      '[REDACTED_FILE_PATH]',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'\b(cardholder(?:Name)?|account(?:Number)?|upi(?:Id)?|notes?|password)\s*[:=]\s*([^\n,;]+)',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=[REDACTED]',
    );
    return result;
  }

  @visibleForTesting
  String buildReport(Map<String, String> deviceDetails) {
    final buffer = StringBuffer()
      ..writeln('CardVault diagnostic log')
      ..writeln('Generated: ${DateTime.now().toUtc().toIso8601String()}')
      ..writeln('Current session: $_sessionId')
      ..writeln('Retention: ${_retention.inHours} hours')
      ..writeln('Maximum retained entries: $_maximumEntries')
      ..writeln(
        'Maximum retained log data: ${_maximumPlaintextBytes ~/ 1024} KB before encryption',
      )
      ..writeln();

    for (final entry in deviceDetails.entries) {
      buffer.writeln('${entry.key}: ${sanitize(entry.value)}');
    }

    buffer
      ..writeln()
      ..writeln(
        'Collected logs (${_entries.length} entries${_discardedEntryCount == 0 ? '' : ', $_discardedEntryCount older entries omitted'})',
      )
      ..writeln('----------------------------------------');
    if (_entries.isEmpty) {
      buffer.writeln('No diagnostic entries were captured in this session.');
    } else {
      for (final entry in _entries) {
        buffer.writeln(entry);
      }
    }
    return buffer.toString();
  }

  Future<File> exportRecentLogs(Map<String, String> deviceDetails) async {
    record('Support', 'Preparing recent diagnostic logs for sharing');
    await _restoreFuture;
    await flush();
    final temporaryDirectory = await getTemporaryDirectory();
    final directory = Directory('${temporaryDirectory.path}/support_logs');
    await directory.create(recursive: true);
    final file = File('${directory.path}/cardvault-recent-logs.txt');
    await file.writeAsString(buildReport(deviceDetails), flush: true);
    return file;
  }

  Future<void> flush() async {
    if (!_restoreStarted) {
      await initializePersistence();
    } else {
      await _restoreFuture;
    }
    _persistTimer?.cancel();
    _persistTimer = null;
    _pruneExpiredEntries();
    final snapshot = List<String>.unmodifiable(_entries);
    _persistenceTail = _persistenceTail
        .catchError((_) {})
        .then((_) => _store.save(snapshot));
    try {
      await _persistenceTail;
    } catch (_) {
      _reportPersistenceFailure();
    }
  }

  Future<void> _restorePersistedLogs() async {
    try {
      final restored = await _store.load();
      final cutoff = DateTime.now().toUtc().subtract(_retention);
      final retained = restored.where((entry) => _entryIsAfter(entry, cutoff));
      _entries
        ..insertAll(0, retained)
        ..removeRange(
          0,
          (_entries.length - _maximumEntries).clamp(0, _entries.length),
        );
    } catch (_) {
      _reportPersistenceFailure();
    } finally {
      _restoreComplete = true;
      _schedulePersist();
    }
  }

  bool _entryIsAfter(String entry, DateTime cutoff) {
    final closingBracket = entry.indexOf(']');
    if (!entry.startsWith('[') || closingBracket <= 1) return false;
    final timestamp = DateTime.tryParse(entry.substring(1, closingBracket));
    return timestamp != null && timestamp.toUtc().isAfter(cutoff);
  }

  void _pruneExpiredEntries() {
    final cutoff = DateTime.now().toUtc().subtract(_retention);
    _entries.removeWhere((entry) => !_entryIsAfter(entry, cutoff));
    var retainedBytes = _entries.fold<int>(
      0,
      (total, entry) => total + utf8.encode(entry).length + 3,
    );
    var removedForSize = 0;
    while (_entries.isNotEmpty && retainedBytes > _maximumPlaintextBytes) {
      retainedBytes -= utf8.encode(_entries.removeAt(0)).length + 3;
      removedForSize++;
    }
    _discardedEntryCount += removedForSize;
  }

  void _schedulePersist() {
    if (!_restoreComplete) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, () => unawaited(flush()));
  }

  void _reportPersistenceFailure() {
    if (_persistenceFailureReported) return;
    _persistenceFailureReported = true;
    final timestamp = DateTime.now().toUtc().toIso8601String();
    _entries.add(
      '[$timestamp] [session=$_sessionId #${++_sequence}] '
      '[Diagnostics] Encrypted diagnostic persistence is unavailable',
    );
  }

  Future<void> _handleNativeDiagnostic(MethodCall call) async {
    if (call.method != 'event' || call.arguments is! Map) return;
    final arguments = Map<Object?, Object?>.from(call.arguments as Map);
    final event = arguments['event']?.toString();
    if (event == null || event.isEmpty) return;
    action(
      'Android',
      event,
      details: {
        if (arguments['status'] != null) 'status': arguments['status'],
        if (arguments['code'] != null) 'code': arguments['code'],
      },
    );
  }
}

class AppLogSpan {
  AppLogSpan._(this._service, this._area, this._operation, this._stopwatch);

  final AppLogService _service;
  final String _area;
  final String _operation;
  final Stopwatch _stopwatch;
  bool _finished = false;

  void complete({Map<String, Object?> details = const <String, Object?>{}}) {
    if (_finished) return;
    _finished = true;
    _stopwatch.stop();
    _service.action(
      _area,
      '$_operation completed',
      details: {'durationMs': _stopwatch.elapsedMilliseconds, ...details},
    );
  }

  void fail(Object error, StackTrace stackTrace) {
    if (_finished) return;
    _finished = true;
    _stopwatch.stop();
    _service.recordFailure(
      '$_operation after ${_stopwatch.elapsedMilliseconds}ms',
      error,
      stackTrace,
      category: 'Failure/$_area',
    );
  }
}

abstract interface class DiagnosticLogStore {
  Future<List<String>> load();
  Future<void> save(List<String> entries);
  Future<void> clear();
}

class EncryptedDiagnosticLogStore implements DiagnosticLogStore {
  static const String _keyName = 'app_diagnostic_log_key_v1';
  static const String _fileName = 'app_diagnostics_v1.enc';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: 'cardvault_diagnostics',
      preferencesKeyPrefix: 'cardvault_diagnostics_',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
      accountName: 'CardVault Diagnostics',
    ),
  );

  @override
  Future<List<String>> load() async {
    var file = await _file(createDirectory: false);
    if (!await file.exists()) {
      final backup = File('${file.path}.bak');
      if (!await backup.exists()) return const <String>[];
      file = backup;
    }
    final decoded = jsonDecode(await _decrypt(await file.readAsString()));
    if (decoded is! List) throw const FormatException('Invalid diagnostic log');
    return decoded.whereType<String>().toList(growable: false);
  }

  @override
  Future<void> save(List<String> entries) async {
    final file = await _file(createDirectory: true);
    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await temporary.writeAsString(
      await _encrypt(jsonEncode(entries)),
      flush: true,
    );
    try {
      if (await backup.exists()) await backup.delete();
      if (await file.exists()) await file.rename(backup.path);
      await temporary.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }

  @override
  Future<void> clear() async {
    final file = await _file(createDirectory: false);
    if (await file.exists()) await file.delete();
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
    final backup = File('${file.path}.bak');
    if (await backup.exists()) await backup.delete();
  }

  Future<File> _file({required bool createDirectory}) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/private_diagnostics');
    if (createDirectory && !await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}/$_fileName');
  }

  Future<encrypt_pkg.Key> _key() async {
    final stored = await _secureStorage.read(key: _keyName);
    if (stored != null && stored.isNotEmpty) {
      return encrypt_pkg.Key.fromBase64(stored);
    }
    final key = encrypt_pkg.Key.fromSecureRandom(32);
    await _secureStorage.write(key: _keyName, value: key.base64);
    return key;
  }

  Future<String> _encrypt(String plaintext) async {
    final iv = encrypt_pkg.IV.fromSecureRandom(16);
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(await _key(), mode: encrypt_pkg.AESMode.gcm),
    );
    return '${iv.base64}:${encrypter.encrypt(plaintext, iv: iv).base64}';
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

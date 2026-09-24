import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_log_service.dart';

/// Opt-in, payload-redacted diagnostics for the NFC state machine.
///
/// NFC payloads, tag identifiers, application identifiers, commands, raw
/// errors, and card data are denied by default. Callers may only emit the
/// small set of protocol-health metadata listed below.
class DebugLogger {
  static const String _developerOptionsEnabledKey = 'developer_options_enabled';
  static bool _runtimeEnabled = false;

  static const Set<String> _allowedFields = {
    'attempt',
    'maxretries',
    'length',
    'count',
    'availability',
    'tagtype',
    'standard',
    'cardtype',
    'sw1sw2',
    'tags',
    'pdoldatalength',
    'totallength',
    'afllength',
    'sfi',
    'firstrecord',
    'lastrecord',
    'recordnum',
    'recordsattempted',
  };

  static bool get isEnabled => _runtimeEnabled;

  static Future<void> initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _runtimeEnabled =
          preferences.getBool(_developerOptionsEnabledKey) ?? false;
    } catch (_) {
      _runtimeEnabled = false;
    }
  }

  static void setEnabled(bool enabled) {
    _runtimeEnabled = enabled;
  }

  static void log(
    String location,
    String message,
    Map<String, dynamic> data,
    String hypothesisId,
  ) {
    if (!isEnabled) return;

    final sanitizedData = _sanitizeData(data);
    developer.log(
      '$message | Data: $sanitizedData',
      name: 'NFC_DIAGNOSTICS',
      time: DateTime.now(),
    );
    AppLogService.instance.record(
      'NFC_DIAGNOSTICS',
      '$location: $message | Data: $sanitizedData',
    );
  }

  @visibleForTesting
  static Map<String, Object> sanitizeForTesting(Map<String, dynamic> data) =>
      _sanitizeData(data);

  static Map<String, Object> _sanitizeData(Map<String, dynamic> data) {
    final sanitized = <String, Object>{};

    for (final entry in data.entries) {
      final normalizedKey = entry.key.toLowerCase();
      final isPresenceFlag = normalizedKey.startsWith('has');
      final isAllowed =
          _allowedFields.contains(normalizedKey) || isPresenceFlag;
      sanitized[entry.key] = isAllowed
          ? _sanitizeAllowedValue(entry.value)
          : '[REDACTED]';
    }

    return sanitized;
  }

  static Object _sanitizeAllowedValue(Object? value) {
    if (value is bool) return value;
    if (value is num) return value;
    if (value is String) {
      return value.length <= 48 ? value : '${value.substring(0, 48)}…';
    }
    if (value is Iterable) {
      return value
          .take(24)
          .map((item) => _sanitizeAllowedValue(item))
          .toList(growable: false);
    }
    return value?.runtimeType.toString() ?? 'null';
  }
}

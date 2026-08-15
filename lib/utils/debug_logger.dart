import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

class DebugLogger {
  static void log(String location, String message, Map<String, dynamic> data, String hypothesisId) {
    if (kDebugMode) {
      final sanitizedData = _sanitizeData(data);
      developer.log(
        '$message | Data: $sanitizedData',
        name: 'NFC_DEBUG',
        time: DateTime.now(),
      );
      print('[NFC_DEBUG] $location: $message | Data: $sanitizedData');
    }
  }

  static Map<String, dynamic> _sanitizeData(Map<String, dynamic> data) {
    final sanitized = <String, dynamic>{};
    
    data.forEach((key, value) {
      final lowerKey = key.toLowerCase();
      
      if (lowerKey.contains('pan') || lowerKey.contains('cardnumber')) {
        if (value is String && value.length >= 4) {
          sanitized[key] = '****${value.substring(value.length - 4)}';
        } else {
          sanitized[key] = '****';
        }
      } else if (lowerKey.contains('expiry') || lowerKey.contains('expirydate')) {
        sanitized[key] = '**/**';
      } else if (lowerKey.contains('name') || lowerKey.contains('cardholder')) {
        if (value is String && value.isNotEmpty) {
          sanitized[key] = '${value[0]}***';
        } else {
          sanitized[key] = '***';
        }
      } else if (lowerKey.contains('cvv') || lowerKey.contains('cvc')) {
        sanitized[key] = '***';
      } else if (value is Map) {
        sanitized[key] = _sanitizeData(value.cast<String, dynamic>());
      } else if (value is List) {
        sanitized[key] = value.map((item) {
          if (item is Map) {
            return _sanitizeData(item.cast<String, dynamic>());
          }
          return item;
        }).toList();
      } else {
        sanitized[key] = value;
      }
    });
    
    return sanitized;
  }
}

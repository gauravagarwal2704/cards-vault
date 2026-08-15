import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  static const MethodChannel _channel = MethodChannel('cards_wallet/security');
  
  int _preventionRefCount = 0;

  Future<void> enableScreenshotPrevention() async {
    _preventionRefCount++;
    if (_preventionRefCount == 1 && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('enableScreenshotPrevention');
      } catch (e) {
        debugPrint('Failed to enable screenshot prevention: $e');
      }
    }
  }

  Future<void> disableScreenshotPrevention() async {
    if (_preventionRefCount > 0) {
      _preventionRefCount--;
    }
    if (_preventionRefCount == 0 && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('disableScreenshotPrevention');
      } catch (e) {
        debugPrint('Failed to disable screenshot prevention: $e');
      }
    }
  }

  void preventScreenshots(BuildContext context) {
    if (Platform.isAndroid) {
      enableScreenshotPrevention();
    }
  }

  void allowScreenshots(BuildContext context) {
    if (Platform.isAndroid) {
      disableScreenshotPrevention();
    }
  }
}


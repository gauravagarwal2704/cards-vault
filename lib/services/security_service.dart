import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_service.dart';
import 'app_log_service.dart';

class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  static const MethodChannel _channel = MethodChannel('cards_wallet/security');

  int _preventionRefCount = 0;
  Future<void>? _initialization;
  bool _isInitialized = false;

  final AuthenticationCoordinator authentication = AuthenticationCoordinator();

  bool get isInitialized => _isInitialized;

  Future<void> initialize() {
    if (_isInitialized) return Future<void>.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    // Install capture protection before the deferred first Flutter frame is
    // released. This also proves the native security channel is ready.
    await enableScreenshotPrevention();
    _isInitialized = true;
  }

  Future<void> enableScreenshotPrevention() async {
    _preventionRefCount++;
    if (_preventionRefCount == 1 && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('enableScreenshotPrevention');
      } catch (e, stackTrace) {
        AppLogService.instance.recordFailure(
          'Enable screenshot prevention',
          e,
          stackTrace,
          category: 'Failure/Security',
        );
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
      } catch (e, stackTrace) {
        AppLogService.instance.recordFailure(
          'Disable screenshot prevention',
          e,
          stackTrace,
          category: 'Failure/Security',
        );
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

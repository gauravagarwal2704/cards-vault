import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_log_service.dart';

enum SupportFeedbackType {
  featureRequest('Feature Request'),
  bugReport('Bug Report'),
  generalFeedback('General Feedback');

  const SupportFeedbackType(this.label);

  final String label;
}

class SupportEmailService {
  SupportEmailService({MethodChannel? channel, FilePicker? filePicker})
    : _channel = channel ?? const MethodChannel('cards_wallet/support'),
      _filePicker = filePicker ?? FilePicker.platform;

  static const String recipient = 'agarwalgaurav.apps@gmail.com';

  final MethodChannel _channel;
  final FilePicker _filePicker;

  /// Opens the platform document picker and writes a sanitized text report to
  /// the location selected by the user. Returns false when the picker is
  /// cancelled without saving.
  Future<bool> downloadLogs() async {
    final span = AppLogService.instance.startSpan(
      'Support',
      'Download diagnostic logs',
    );
    try {
      final details = await _deviceDetails();
      final report = await AppLogService.instance.exportRecentLogs(details);
      final savedPath = await _filePicker.saveFile(
        dialogTitle: 'Save CardVault diagnostic logs',
        fileName: _diagnosticFileName(),
        type: FileType.custom,
        allowedExtensions: const <String>['txt'],
        bytes: await report.readAsBytes(),
      );
      span.complete(
        details: {'outcome': savedPath == null ? 'cancelled' : 'saved'},
      );
      return savedPath != null;
    } catch (error, stackTrace) {
      span.fail(error, stackTrace);
      rethrow;
    }
  }

  Future<void> sendFeedback({
    required SupportFeedbackType type,
    required String comments,
    required bool includeDiagnostics,
  }) async {
    final span = AppLogService.instance.startSpan(
      'Support',
      'Compose feedback email',
      details: {'type': type.name, 'includeDiagnostics': includeDiagnostics},
    );
    try {
      final details = includeDiagnostics
          ? await _deviceDetails()
          : <String, String>{};
      final file = includeDiagnostics
          ? await AppLogService.instance.exportRecentLogs(details)
          : null;
      final body = StringBuffer()
        ..writeln('Hello,')
        ..writeln()
        ..writeln('Type: ${type.label}')
        ..writeln()
        ..writeln('Feedback:')
        ..writeln(comments.trim());
      if (includeDiagnostics) {
        body
          ..writeln()
          ..writeln('----------------')
          ..writeln('Device Info:');
        for (final entry in details.entries) {
          body.writeln('${_detailLabel(entry.key)}: ${entry.value}');
        }
      }

      final arguments = <String, Object>{
        'recipient': recipient,
        'subject': 'CardVault Feedback: ${type.label}',
        'body': body.toString(),
      };
      if (file != null) arguments['attachmentPath'] = file.path;
      await _channel.invokeMethod<void>('composeEmail', arguments);
      span.complete();
    } catch (error, stackTrace) {
      span.fail(error, stackTrace);
      rethrow;
    }
  }

  static String _detailLabel(String key) => switch (key) {
    'appVersion' => 'App Version',
    'packageName' => 'Package Name',
    'platform' => 'Platform',
    'manufacturer' => 'Manufacturer',
    'model' => 'Model',
    'device' => 'Device',
    'product' => 'Product',
    'osVersion' => 'OS Version',
    'sdkInt' => 'SDK',
    'locale' => 'Locale',
    'supportedAbis' => 'Supported ABIs',
    'availableStorageBytes' => 'Available App Storage (bytes)',
    'lowRamDevice' => 'Low-RAM Device',
    'cameraPermission' => 'Camera Permission',
    'processUptimeMs' => 'Device Uptime (ms)',
    _ => key,
  };

  static String _diagnosticFileName() {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final fileSafeTimestamp = timestamp.replaceAll(RegExp(r'[:.]'), '-');
    return 'cardvault-diagnostics-$fileSafeTimestamp.txt';
  }

  Future<Map<String, String>> _deviceDetails() async {
    final details = <String, String>{};
    try {
      final nativeDetails = await _channel.invokeMapMethod<String, dynamic>(
        'getDeviceDetails',
      );
      nativeDetails?.forEach((key, value) {
        if (value != null) details[key] = value.toString();
      });
    } on MissingPluginException {
      // Tests and unsupported desktop platforms use the Dart fallbacks below.
    } on PlatformException catch (error) {
      AppLogService.instance.action(
        'Support',
        'Native device details unavailable',
        details: {'code': error.code},
      );
      // Device metadata is helpful but should never prevent log sharing.
    }

    details.putIfAbsent('platform', () => Platform.operatingSystem);
    details.putIfAbsent('osVersion', () => Platform.operatingSystemVersion);
    details.putIfAbsent('locale', () => Platform.localeName);

    try {
      final package = await PackageInfo.fromPlatform();
      details['appVersion'] = '${package.version} (${package.buildNumber})';
      details['packageName'] = package.packageName;
    } on MissingPluginException {
      details.putIfAbsent('appVersion', () => 'Unavailable');
    } on PlatformException {
      details.putIfAbsent('appVersion', () => 'Unavailable');
    }
    return details;
  }
}

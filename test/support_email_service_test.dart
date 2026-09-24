import 'dart:io';

import 'package:cards_wallet/services/app_log_service.dart';
import 'package:cards_wallet/services/support_email_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TemporaryPathProvider extends PathProviderPlatform {
  _TemporaryPathProvider(this.path);

  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

class _RecordingFilePicker extends FilePicker {
  String? fileName;
  FileType? fileType;
  List<String>? allowedExtensions;
  Uint8List? bytes;
  String? result = 'content://downloads/cardvault-diagnostics.txt';

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    this.fileName = fileName;
    fileType = type;
    this.allowedExtensions = allowedExtensions;
    this.bytes = bytes;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'feedback email includes recipient, device info, and redacted log file',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'cardvault-support-test-',
      );
      final previousPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TemporaryPathProvider(
        temporaryDirectory.path,
      );
      const channel = MethodChannel('cards_wallet/support-test');
      final filePicker = _RecordingFilePicker();
      MethodCall? composeCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getDeviceDetails') {
              return <String, Object>{
                'platform': 'Android',
                'manufacturer': 'Example',
                'model': 'Test Phone',
                'osVersion': '16',
                'sdkInt': '36',
              };
            }
            if (call.method == 'composeEmail') {
              composeCall = call;
              return true;
            }
            return null;
          });

      try {
        AppLogService.instance.record('Test', 'PAN 4111111111111111');
        final service = SupportEmailService(
          channel: channel,
          filePicker: filePicker,
        );
        await service.sendFeedback(
          type: SupportFeedbackType.bugReport,
          comments: 'The scanner closed unexpectedly.',
          includeDiagnostics: true,
        );

        final arguments = Map<String, Object?>.from(
          composeCall!.arguments as Map,
        );
        expect(arguments['recipient'], SupportEmailService.recipient);
        expect(arguments['subject'], 'CardVault Feedback: Bug Report');
        expect(arguments['body'], contains('The scanner closed unexpectedly.'));
        expect(arguments['body'], contains('Platform: Android'));
        expect(arguments['body'], contains('Model: Test Phone'));

        final attachment = File(arguments['attachmentPath']! as String);
        expect(await attachment.exists(), isTrue);
        final contents = await attachment.readAsString();
        expect(contents, contains('[REDACTED_CARD_NUMBER]'));
        expect(contents, isNot(contains('4111111111111111')));

        expect(await service.downloadLogs(), isTrue);
        expect(filePicker.fileName, startsWith('cardvault-diagnostics-'));
        expect(filePicker.fileName, endsWith('.txt'));
        expect(filePicker.fileType, FileType.custom);
        expect(filePicker.allowedExtensions, const <String>['txt']);
        final downloadedContents = String.fromCharCodes(filePicker.bytes!);
        expect(downloadedContents, contains('CardVault diagnostic log'));
        expect(downloadedContents, contains('[REDACTED_CARD_NUMBER]'));
        expect(downloadedContents, isNot(contains('4111111111111111')));

        filePicker.result = null;
        expect(await service.downloadLogs(), isFalse);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        PathProviderPlatform.instance = previousPathProvider;
        await temporaryDirectory.delete(recursive: true);
      }
    },
  );
}

import 'package:cards_wallet/services/card_text_ocr_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses Android plain-text OCR into ordered synthetic lines', () async {
    const channel = MethodChannel('cards_wallet/card_text_ocr_plain_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'recognizeImage');
          expect((call.arguments as Map)['profile'], 'digits');
          return <String, Object>{
            'text': '4111 1111 1111 1111\n12/30',
            'confidence': 0.82,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final result = await CardTextOcrService(channel: channel)
        .recognizeImage('/prepared.jpg', profile: CardTextOcrProfile.digits);

    expect(result.lines.map((line) => line.text), [
      '4111 1111 1111 1111',
      '12/30',
    ]);
    expect(result.lines.first.top, isNotNull);
    expect(result.confidence, 0.82);
  });

  test('preserves Apple Vision line geometry', () async {
    const channel = MethodChannel('cards_wallet/card_text_ocr_vision_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => <String, Object>{
            'lines': <Map<String, Object>>[
              <String, Object>{
                'text': 'TEST USER',
                'confidence': 0.91,
                'left': 0.1,
                'top': 0.72,
                'width': 0.4,
                'height': 0.08,
              },
            ],
            'confidence': 0.91,
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final result = await CardTextOcrService(channel: channel)
        .recognizeImage('/prepared.jpg');

    expect(result.lines.single.text, 'TEST USER');
    expect(result.lines.single.left, 0.1);
    expect(result.lines.single.top, 0.72);
  });

  test('does not leak native OCR details through exceptions', () async {
    const channel = MethodChannel('cards_wallet/card_text_ocr_error_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(
            code: 'internal_native_failure',
            message: 'sensitive implementation detail',
          ),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    expect(
      () => CardTextOcrService(channel: channel).recognizeImage('/bad.jpg'),
      throwsA(isA<CardTextOcrException>()),
    );
  });
}

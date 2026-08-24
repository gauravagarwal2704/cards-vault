import 'package:cards_wallet/services/card_field_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final resolver = CardFieldResolver();

  CardTextObservation observation(
    String text, {
    int frame = 0,
    String? sourceId,
    bool isComposite = false,
    double left = 0.08,
    double top = 0.5,
    double width = 0.75,
    double height = 0.08,
  }) {
    return CardTextObservation(
      text: text,
      frameIndex: frame,
      sourceId: sourceId,
      isComposite: isComposite,
      recognizerConfidence: 0.82,
      box: NormalizedTextBox(
        left: left,
        top: top,
        width: width,
        height: height,
      ),
    );
  }

  test('resolves a valid PAN while rejecting a nearby invalid sequence', () {
    final result = resolver.resolve([
      observation('4111 1111 1111 1112', top: 0.38),
      observation('4111 1111 1111 1111', top: 0.46),
    ]);

    expect(result.cardNumber.value, '4111111111111111');
    expect(result.cardNumber.confidence, greaterThan(0.75));
  });

  test(
    'corrects common digit-shaped OCR characters before Luhn validation',
    () {
      final result = resolver.resolve([
        observation('4I11 1111 1111 1111', top: 0.45),
      ]);

      expect(result.cardNumber.value, '4111111111111111');
    },
  );

  test('raises confidence when independent frames agree', () {
    final singleFrame = resolver.resolve([
      observation('4111 1111 1111 1111', frame: 0),
    ]);
    final multipleFrames = resolver.resolve([
      observation('4111 1111 1111 1111', frame: 0),
      observation('4111 1111 1111 1111', frame: 1),
      observation('4111 1111 1111 1111', frame: 2),
    ]);

    expect(multipleFrames.cardNumber.supportingFrames, 3);
    expect(
      multipleFrames.cardNumber.confidence,
      greaterThan(singleFrame.cardNumber.confidence),
    );
  });

  test('joins a PAN printed as vertically stacked four-digit groups', () {
    final result = resolver.resolve([
      observation('4111', left: 0.08, top: 0.12, width: 0.2, height: 0.06),
      observation('1111', left: 0.08, top: 0.20, width: 0.2, height: 0.06),
      observation('1111', left: 0.08, top: 0.28, width: 0.2, height: 0.06),
      observation('1111', left: 0.08, top: 0.36, width: 0.2, height: 0.06),
      observation('12/30', left: 0.08, top: 0.48, width: 0.2, height: 0.06),
      observation('123', left: 0.08, top: 0.56, width: 0.15, height: 0.06),
    ]);

    expect(result.cardNumber.value, '4111111111111111');
    expect(result.cardNumber.confidence, greaterThan(0.75));
  });

  test('never splices digit groups from different OCR passes', () {
    final result = resolver.resolve([
      observation(
        '4111',
        sourceId: 'original',
        left: 0.08,
        top: 0.12,
        width: 0.2,
        height: 0.06,
      ),
      observation(
        '1111',
        sourceId: 'enhanced',
        left: 0.08,
        top: 0.20,
        width: 0.2,
        height: 0.06,
      ),
      observation(
        '1111',
        sourceId: 'original',
        left: 0.08,
        top: 0.28,
        width: 0.2,
        height: 0.06,
      ),
      observation(
        '1111',
        sourceId: 'enhanced',
        left: 0.08,
        top: 0.36,
        width: 0.2,
        height: 0.06,
      ),
    ]);

    expect(result.cardNumber.value, isNull);
  });

  test('requires PAN agreement across two physical camera frames', () {
    final oneFrame = resolver.resolve([
      observation('4111 1111 1111 1111', frame: 0),
    ], minimumPanSupportingFrames: 2);
    final twoFrames = resolver.resolve([
      observation('4111 1111 1111 1111', frame: 0),
      observation('4111 1111 1111 1111', frame: 1),
    ], minimumPanSupportingFrames: 2);

    expect(oneFrame.cardNumber.value, isNull);
    expect(oneFrame.cardNumber.supportingFrames, 1);
    expect(twoFrames.cardNumber.value, '4111111111111111');
    expect(twoFrames.cardNumber.supportingFrames, 2);
  });

  test('accepts one clear Luhn-valid PAN with the default policy', () {
    final result = resolver.resolve([
      observation('4111 1111 1111 1111', frame: 0),
    ]);

    expect(result.cardNumber.value, '4111111111111111');
    expect(result.cardNumber.supportingFrames, 1);
  });

  test('reports the OCR pass that supplied the winning PAN evidence', () {
    final result = resolver.resolve([
      observation(
        '4111 1111 1111 1111',
        frame: 0,
        sourceId: 'frame_0_crop_enhanced',
      ),
    ]);

    expect(result.cardNumber.sourceId, 'frame_0_crop_enhanced');
  });

  test('rejects similarly ranked conflicting PAN candidates', () {
    final result = resolver.resolve([
      observation('4111 1111 1111 1111', frame: 0),
      observation('4111 1111 1111 1111', frame: 1),
      observation('4012 8888 8888 1881', frame: 2),
      observation('4012 8888 8888 1881', frame: 3),
    ], minimumPanSupportingFrames: 2);

    expect(result.cardNumber.value, isNull);
    expect(result.cardNumber.isAmbiguous, isTrue);
  });

  test('does not trust composite ML Kit block order for a PAN', () {
    final result = resolver.resolve([
      observation(
        '4111',
        isComposite: true,
        top: 0.12,
        width: 0.2,
        height: 0.06,
      ),
      observation(
        '1111',
        isComposite: true,
        top: 0.20,
        width: 0.2,
        height: 0.06,
      ),
      observation(
        '1111',
        isComposite: true,
        top: 0.28,
        width: 0.2,
        height: 0.06,
      ),
      observation(
        '1111',
        isComposite: true,
        top: 0.36,
        width: 0.2,
        height: 0.06,
      ),
    ]);

    expect(result.cardNumber.value, isNull);
  });

  test('uses labels and geometry to resolve expiry and cardholder name', () {
    final futureYear = ((DateTime.now().year + 3) % 100).toString().padLeft(
      2,
      '0',
    );
    final result = resolver.resolve([
      observation('VALID THRU 08/$futureYear', top: 0.58),
      observation('GAURAV AGARWAL', top: 0.76),
      observation('PLATINUM DEBIT CARD', top: 0.2),
      observation('EXAMPLE BANK', top: 0.1),
    ]);

    expect(result.expiryDate.value, '08/$futureYear');
    expect(result.cardholderName.value, 'GAURAV AGARWAL');
  });

  test('does not return issuer or product labels as a person name', () {
    final result = resolver.resolve([
      observation('EXAMPLE BANK', top: 0.12),
      observation('VISA SIGNATURE', top: 0.8),
      observation('ISSUED BY', top: 0.7),
    ]);

    expect(result.cardholderName.value, isNull);
  });
}

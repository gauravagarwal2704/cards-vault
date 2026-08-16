import 'package:cards_wallet/services/card_field_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final resolver = CardFieldResolver();

  CardTextObservation observation(
    String text, {
    int frame = 0,
    double top = 0.5,
  }) {
    return CardTextObservation(
      text: text,
      frameIndex: frame,
      recognizerConfidence: 0.82,
      box: NormalizedTextBox(
        left: 0.08,
        top: top,
        width: 0.75,
        height: 0.08,
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

  test('corrects common digit-shaped OCR characters before Luhn validation', () {
    final result = resolver.resolve([
      observation('4I11 1111 1111 1111', top: 0.45),
    ]);

    expect(result.cardNumber.value, '4111111111111111');
  });

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

  test('uses labels and geometry to resolve expiry and cardholder name', () {
    final futureYear = ((DateTime.now().year + 3) % 100)
        .toString()
        .padLeft(2, '0');
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
    ]);

    expect(result.cardholderName.value, isNull);
  });
}

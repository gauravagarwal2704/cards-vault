import 'package:cards_wallet/models/card_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sensitive card values use dot masks', () {
    final card = CardData(
      encryptedCardNumber: 'encrypted-number',
      encryptedExpiryDate: 'encrypted-expiry',
      encryptedCvv: 'encrypted-cvv',
      lastFourDigits: '1121',
      cardType: 'Visa',
    );

    expect(card.maskedCardNumber, '•••• •••• •••• 1121');
    expect(card.maskedCvv, '•••');
    expect(CardData.hiddenExpiryDate, '••/••');
    expect(CardData.hiddenCardNumber, '•••• •••• •••• ••••');
  });
}

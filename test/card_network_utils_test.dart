import 'package:flutter_test/flutter_test.dart';
import 'package:cards_wallet/utils/card_network_utils.dart';
import 'package:cards_wallet/widgets/wallet_card.dart';

void main() {
  group('networkFromCardType', () {
    test('accepts every label variant older builds persisted', () {
      const cases = {
        'Amex': CardNetwork.amex,
        'amex': CardNetwork.amex,
        'American Express': CardNetwork.amex,
        'Visa': CardNetwork.visa,
        'Mastercard': CardNetwork.mastercard,
        'RuPay': CardNetwork.rupay,
        'Diners Club': CardNetwork.dinersClub,
        'UnionPay': CardNetwork.unionPay,
        'Maestro': CardNetwork.maestro,
        'Unknown': CardNetwork.unknown,
        '': CardNetwork.unknown,
      };

      cases.forEach((label, expected) {
        expect(
          CardNetworkUtils.networkFromCardType(label),
          expected,
          reason: 'label "$label"',
        );
      });
    });

    test('round-trips the canonical label written on save', () {
      for (final number in ['4111111111111111', '371449635398431', '6521999999999999']) {
        final label = CardNetworkUtils.cardTypeFromNumber(number);
        expect(
          CardNetworkUtils.networkFromCardType(label),
          CardNetworkUtils.detectNetwork(number),
          reason: 'number starting ${number.substring(0, 4)}',
        );
      }
    });
  });

  group('detectNetwork', () {
    test('prefers RuPay over Discover for Indian 6521/6522 BINs', () {
      expect(CardNetworkUtils.detectNetwork('6521999999999999'), CardNetwork.rupay);
      expect(CardNetworkUtils.detectNetwork('6522999999999999'), CardNetwork.rupay);
      expect(CardNetworkUtils.detectNetwork('6011999999999999'), CardNetwork.discover);
      expect(CardNetworkUtils.detectNetwork('6534999999999999'), CardNetwork.discover);
    });

    test('detects the common networks', () {
      expect(CardNetworkUtils.detectNetwork('4111 1111 1111 1111'), CardNetwork.visa);
      expect(CardNetworkUtils.detectNetwork('5500 0000 0000 0004'), CardNetwork.mastercard);
      expect(CardNetworkUtils.detectNetwork('3714 496353 98431'), CardNetwork.amex);
      expect(CardNetworkUtils.detectNetwork('6070 9999 9999 9999'), CardNetwork.rupay);
      expect(CardNetworkUtils.detectNetwork('6212 9999 9999 9999'), CardNetwork.unionPay);
      expect(CardNetworkUtils.detectNetwork('3600 0000 0000 08'), CardNetwork.dinersClub);
      expect(CardNetworkUtils.detectNetwork(''), CardNetwork.unknown);
    });
  });
}

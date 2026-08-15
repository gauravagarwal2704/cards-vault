import '../widgets/wallet_card.dart';

class CardNetworkUtils {
  static CardNetwork detectNetwork(String cardNumber) {
    final cleaned = cardNumber.replaceAll(RegExp(r'[\s\-]'), '');
    
    if (cleaned.isEmpty) return CardNetwork.unknown;
    
    // American Express: starts with 34 or 37
    if (cleaned.startsWith('34') || cleaned.startsWith('37')) {
      return CardNetwork.amex;
    }
    
    // Visa: starts with 4
    if (cleaned.startsWith('4')) {
      return CardNetwork.visa;
    }
    
    // Mastercard: starts with 51-55 or 2221-2720
    if (cleaned.length >= 2) {
      final firstTwo = int.tryParse(cleaned.substring(0, 2)) ?? 0;
      if (firstTwo >= 51 && firstTwo <= 55) {
        return CardNetwork.mastercard;
      }
    }
    if (cleaned.length >= 4) {
      final firstFour = int.tryParse(cleaned.substring(0, 4)) ?? 0;
      if (firstFour >= 2221 && firstFour <= 2720) {
        return CardNetwork.mastercard;
      }
    }
    
    // Discover: 6011 is checked ahead of RuPay's broader 60 prefix.
    if (cleaned.startsWith('6011')) {
      return CardNetwork.discover;
    }

    // RuPay: 60, 6521, 6522, 508, 81, 82. Checked before Discover's 65 range
    // because Indian RuPay BINs 6521/6522 fall inside it.
    if (cleaned.startsWith('60') ||
        cleaned.startsWith('6521') ||
        cleaned.startsWith('6522') ||
        cleaned.startsWith('508') ||
        cleaned.startsWith('81') ||
        cleaned.startsWith('82')) {
      return CardNetwork.rupay;
    }

    // Discover: 622126-622925, 644-649, 65
    if (cleaned.startsWith('65') ||
        (cleaned.length >= 3 && 
         int.tryParse(cleaned.substring(0, 3)) != null &&
         int.parse(cleaned.substring(0, 3)) >= 644 &&
         int.parse(cleaned.substring(0, 3)) <= 649)) {
      return CardNetwork.discover;
    }
    
    // JCB: starts with 3528-3589
    if (cleaned.length >= 4) {
      final firstFour = int.tryParse(cleaned.substring(0, 4)) ?? 0;
      if (firstFour >= 3528 && firstFour <= 3589) {
        return CardNetwork.jcb;
      }
    }
    
    // Diners Club: starts with 36, 38, or 300-305
    if (cleaned.startsWith('36') || cleaned.startsWith('38')) {
      return CardNetwork.dinersClub;
    }
    if (cleaned.length >= 3) {
      final firstThree = int.tryParse(cleaned.substring(0, 3)) ?? 0;
      if (firstThree >= 300 && firstThree <= 305) {
        return CardNetwork.dinersClub;
      }
    }
    
    // UnionPay: starts with 62
    if (cleaned.startsWith('62')) {
      return CardNetwork.unionPay;
    }
    
    // Maestro: 5018, 5020, 5038, 5893, 6304, 6759, 6761, 6762, 6763
    if (cleaned.length >= 4) {
      final firstFour = cleaned.substring(0, 4);
      if (['5018', '5020', '5038', '5893', '6304', '6759', '6761', '6762', '6763'].contains(firstFour)) {
        return CardNetwork.maestro;
      }
    }
    
    return CardNetwork.unknown;
  }
  
  /// Maps a stored `cardType` string back onto a network. Used where only the
  /// card type is available and the number itself is still encrypted.
  ///
  /// Cards saved by older builds carry inconsistent labels for the same network
  /// ("Amex" vs "American Express"), so the label is normalised before matching.
  static CardNetwork networkFromCardType(String cardType) {
    switch (cardType.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')) {
      case 'visa':
        return CardNetwork.visa;
      case 'mastercard':
      case 'mc':
        return CardNetwork.mastercard;
      case 'amex':
      case 'americanexpress':
        return CardNetwork.amex;
      case 'discover':
        return CardNetwork.discover;
      case 'jcb':
        return CardNetwork.jcb;
      case 'rupay':
        return CardNetwork.rupay;
      case 'diners':
      case 'dinersclub':
        return CardNetwork.dinersClub;
      case 'unionpay':
        return CardNetwork.unionPay;
      case 'maestro':
        return CardNetwork.maestro;
      case 'gpay':
      case 'googlepay':
        return CardNetwork.gpay;
      default:
        return CardNetwork.unknown;
    }
  }

  /// Canonical label to persist on [CardData.cardType] for a card number.
  static String cardTypeFromNumber(String cardNumber) =>
      getNetworkName(detectNetwork(cardNumber));

  static String getNetworkName(CardNetwork network) {
    switch (network) {
      case CardNetwork.visa:
        return 'Visa';
      case CardNetwork.mastercard:
        return 'Mastercard';
      case CardNetwork.amex:
        return 'American Express';
      case CardNetwork.discover:
        return 'Discover';
      case CardNetwork.jcb:
        return 'JCB';
      case CardNetwork.dinersClub:
        return 'Diners Club';
      case CardNetwork.unionPay:
        return 'UnionPay';
      case CardNetwork.rupay:
        return 'RuPay';
      case CardNetwork.gpay:
        return 'Google Pay';
      case CardNetwork.maestro:
        return 'Maestro';
      case CardNetwork.unknown:
        return 'Unknown';
    }
  }

  static String formatCardNumber(String cardNumber, CardNetwork network) {
    final cleaned = cardNumber.replaceAll(RegExp(r'[\s\-]'), '');
    
    if (network == CardNetwork.amex) {
      // AMEX format: 4-6-5
      if (cleaned.length <= 4) return cleaned;
      if (cleaned.length <= 10) {
        return '${cleaned.substring(0, 4)} ${cleaned.substring(4)}';
      }
      return '${cleaned.substring(0, 4)} ${cleaned.substring(4, 10)} ${cleaned.substring(10)}';
    } else {
      // Standard format: 4-4-4-4
      final buffer = StringBuffer();
      for (int i = 0; i < cleaned.length; i++) {
        if (i > 0 && i % 4 == 0) {
          buffer.write(' ');
        }
        buffer.write(cleaned[i]);
      }
      return buffer.toString();
    }
  }

  static int getCardLength(CardNetwork network) {
    switch (network) {
      case CardNetwork.amex:
        return 15;
      case CardNetwork.dinersClub:
        return 14;
      case CardNetwork.maestro:
      case CardNetwork.unionPay:
        return 19; // Can be 12-19, using max
      default:
        return 16;
    }
  }

  static int getCvvLength(CardNetwork network) {
    return network == CardNetwork.amex ? 4 : 3;
  }

  static String getCvvLabel(CardNetwork network) {
    return network == CardNetwork.amex ? 'CID (4 digits)' : 'CVV (3 digits)';
  }

  static String getCardFormat(CardNetwork network) {
    return network == CardNetwork.amex ? '4-6-5' : '4-4-4-4';
  }
}


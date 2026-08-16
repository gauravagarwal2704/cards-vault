import 'package:flutter/services.dart';

import '../widgets/wallet_card.dart';
import 'card_network_utils.dart';

class CardNumberFormatter extends TextInputFormatter {
  final CardNetwork? network;

  CardNumberFormatter({this.network});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    if (text.isEmpty) {
      return newValue;
    }

    // Remove all non-digit characters
    final digitsOnly = text.replaceAll(RegExp(r'\D'), '');

    if (digitsOnly.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Get max length based on network
    final maxLength = _getMaxLengthForNetwork(network);
    if (digitsOnly.length > maxLength) {
      return oldValue;
    }

    // Detect network if not provided
    final detectedNetwork =
        network ?? CardNetworkUtils.detectNetwork(digitsOnly);

    // Format based on network
    final formatted = CardNetworkUtils.formatCardNumber(
      digitsOnly,
      detectedNetwork,
    );

    // Calculate cursor position more accurately
    final int cursorPosition = newValue.selection.baseOffset;

    // Count digits before cursor in NEW value
    int digitsBeforeCursorInNew = 0;
    for (int i = 0; i < cursorPosition && i < newValue.text.length; i++) {
      if (RegExp(r'\d').hasMatch(newValue.text[i])) {
        digitsBeforeCursorInNew++;
      }
    }

    // Find corresponding position in formatted text
    int newCursorPosition = 0;
    int digitsSeen = 0;

    for (int i = 0; i < formatted.length; i++) {
      if (RegExp(r'\d').hasMatch(formatted[i])) {
        digitsSeen++;
        if (digitsSeen == digitsBeforeCursorInNew) {
          newCursorPosition = i + 1;
          break;
        }
      }
    }

    // If we haven't found the position yet, place at end
    if (newCursorPosition == 0 && formatted.isNotEmpty) {
      newCursorPosition = formatted.length;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCursorPosition),
    );
  }

  int _getMaxLengthForNetwork(CardNetwork? network) {
    switch (network) {
      case CardNetwork.amex:
        return 15;
      case CardNetwork.dinersClub:
        return 14;
      case CardNetwork.visa:
      case CardNetwork.mastercard:
      case CardNetwork.discover:
      case CardNetwork.jcb:
      case CardNetwork.unionPay:
      case CardNetwork.rupay:
        return 16;
      default:
        return 19;
    }
  }
}

class CvvFormatter extends TextInputFormatter {
  final CardNetwork? network;

  CvvFormatter({this.network});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    final digitsOnly = text.replaceAll(RegExp(r'\D'), '');

    // Get max length based on network
    final maxLength = network == CardNetwork.amex ? 4 : 3;

    if (digitsOnly.length > maxLength) {
      return oldValue;
    }

    return TextEditingValue(
      text: digitsOnly,
      selection: TextSelection.collapsed(offset: digitsOnly.length),
    );
  }
}

class ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    final digitsOnly = text.replaceAll(RegExp(r'\D'), '');

    if (digitsOnly.isEmpty) {
      return newValue.copyWith(text: '');
    }

    if (digitsOnly.length > 4) {
      return oldValue;
    }

    String formatted = digitsOnly.substring(0, digitsOnly.length.clamp(0, 2));
    if (digitsOnly.length >= 3) {
      formatted += '/${digitsOnly.substring(2, digitsOnly.length.clamp(2, 4))}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

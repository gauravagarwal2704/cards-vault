class HexUtils {
  static String bytesToHex(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
  }

  static List<int> hexToBytes(String hex) {
    hex = hex.replaceAll(' ', '');
    if (hex.length % 2 != 0) {
      throw const FormatException('Hex string must have an even length');
    }
    
    List<int> bytes = [];
    for (int i = 0; i < hex.length; i += 2) {
      String hexByte = hex.substring(i, i + 2);
      bytes.add(int.parse(hexByte, radix: 16));
    }
    return bytes;
  }

  static String formatCardNumber(String pan) {
    pan = pan.replaceAll(' ', '');
    
    if (pan.length >= 16) {
      return '${pan.substring(0, 4)} ${pan.substring(4, 8)} ${pan.substring(8, 12)} ${pan.substring(12)}';
    } else if (pan.length >= 15) {
      return '${pan.substring(0, 4)} ${pan.substring(4, 10)} ${pan.substring(10)}';
    }
    
    return pan;
  }

  static String formatExpiry(String expiry) {
    if (expiry.length >= 4) {
      String year = expiry.substring(0, 2);
      String month = expiry.substring(2, 4);
      return '$month/$year';
    }
    return expiry;
  }

  static String cleanPAN(String pan) {
    String cleaned = '';
    for (int i = 0; i < pan.length; i++) {
      if (pan[i].contains(RegExp(r'[0-9]'))) {
        cleaned += pan[i];
      } else if (pan[i] == 'F' || pan[i] == 'f') {
        break;
      }
    }
    return cleaned;
  }
}


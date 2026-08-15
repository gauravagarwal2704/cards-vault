import '../utils/hex_utils.dart';

class ApduCommands {
  static const String selectPpse = "00A404000E325041592E5359532E444446303100";
  
  static String selectAID(String aid) {
    String aidHex = aid.replaceAll(' ', '');
    int aidLength = (aidHex.length / 2).floor();
    String lengthHex = aidLength.toRadixString(16).padLeft(2, '0');
    return "00A40400$lengthHex${aidHex}00";
  }

  static const String gpoCommand = "80A80000028300";
  
  static String readRecord(int recordNumber, int sfi) {
    String record = recordNumber.toRadixString(16).padLeft(2, '0');
    String sfiValue = ((sfi << 3) | 0x04).toRadixString(16).padLeft(2, '0');
    return "00B2$record${sfiValue}00";
  }
}

class TLVParser {
  static Map<String, dynamic> parse(List<int> data) {
    Map<String, dynamic> result = {};
    int index = 0;

    while (index < data.length) {
      if (index >= data.length) break;

      String tag = _readTag(data, index);
      if (tag.isEmpty) break;
      
      index += (tag.length / 2).floor();

      if (index >= data.length) break;

      int length = _readLength(data, index);
      int lengthBytes = _getLengthBytes(data[index]);
      index += lengthBytes;

      if (index + length > data.length) break;

      List<int> value = data.sublist(index, index + length);
      result[tag] = value;
      index += length;
    }

    return result;
  }

  static String _readTag(List<int> data, int index) {
    if (index >= data.length) return '';
    
    String tag = data[index].toRadixString(16).padLeft(2, '0').toUpperCase();
    
    if ((data[index] & 0x1F) == 0x1F) {
      index++;
      if (index < data.length) {
        tag += data[index].toRadixString(16).padLeft(2, '0').toUpperCase();
      }
    }
    
    return tag;
  }

  static int _readLength(List<int> data, int index) {
    if (index >= data.length) return 0;
    
    int firstByte = data[index];
    
    if ((firstByte & 0x80) == 0) {
      return firstByte;
    } else {
      int numLengthBytes = firstByte & 0x7F;
      int length = 0;
      
      for (int i = 1; i <= numLengthBytes && (index + i) < data.length; i++) {
        length = (length << 8) | data[index + i];
      }
      
      return length;
    }
  }

  static int _getLengthBytes(int firstByte) {
    if ((firstByte & 0x80) == 0) {
      return 1;
    } else {
      return 1 + (firstByte & 0x7F);
    }
  }

  static String? findTag(Map<String, dynamic> tlvData, String tag) {
    if (tlvData.containsKey(tag)) {
      List<int> value = tlvData[tag];
      return HexUtils.bytesToHex(value);
    }
    return null;
  }

  static List<int>? findTagBytes(Map<String, dynamic> tlvData, String tag) {
    if (tlvData.containsKey(tag)) {
      return tlvData[tag];
    }
    return null;
  }
}


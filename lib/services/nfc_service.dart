import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import '../models/card_data.dart';
import '../utils/hex_utils.dart';
import '../utils/debug_logger.dart';
import '../utils/card_network_utils.dart';
import 'apdu_commands.dart';

class NfcService {
  static final NfcService _instance = NfcService._internal();
  factory NfcService() => _instance;
  NfcService._internal();
  
  Future<String> _transceiveWithRetry(String command, {int maxRetries = 3}) async {
    int attempts = 0;
    Exception? lastException;
    
    while (attempts < maxRetries) {
      try {
        attempts++;
        String response = await FlutterNfcKit.transceive(command);
        return response;
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        // #region agent log
        DebugLogger.log('nfc_service.dart:transceive_retry', 'Transceive attempt failed', 
          {'attempt': attempts, 'maxRetries': maxRetries, 'error': e.toString()}, 'H5');
        // #endregion
        
        if (attempts < maxRetries) {
          await Future.delayed(Duration(milliseconds: 100 * attempts));
        }
      }
    }
    
    throw lastException ?? Exception('Transceive failed after $maxRetries attempts');
  }

  Future<NFCAvailability> getNfcAvailability() async {
    try {
      // #region agent log
      DebugLogger.log('nfc_service.dart:13', 'Checking NFC availability', {}, 'H1');
      // #endregion
      NFCAvailability availability = await FlutterNfcKit.nfcAvailability;
      // #region agent log
      DebugLogger.log('nfc_service.dart:16', 'NFC availability response', {'availability': availability.toString()}, 'H1');
      // #endregion
      return availability;
    } catch (e) {
      // #region agent log
      DebugLogger.log('nfc_service.dart:18', 'NFC availability check exception', {'error': e.toString()}, 'H1');
      // #endregion
      return NFCAvailability.not_supported;
    }
  }

  Future<bool> isNfcAvailable() async {
    return await getNfcAvailability() == NFCAvailability.available;
  }

  Future<CardData?> readCard() async {
    if (Platform.isIOS) {
      throw PlatformException(
        code: 'IOS_NOT_SUPPORTED',
        message: 'NFC Card reading not supported on iOS, please use Camera',
      );
    }

    try {
      // #region agent log
      DebugLogger.log('nfc_service.dart:30', 'Starting NFC poll', {}, 'H2');
      // #endregion
      NFCTag tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 60),
        iosMultipleTagMessage: "Multiple cards detected!",
        iosAlertMessage: "Hold your card near the device",
        androidPlatformSound: true,
      );
      // #region agent log
      DebugLogger.log('nfc_service.dart:36', 'NFC tag detected', {'tagType': tag.type.toString(), 'id': tag.id, 'standard': tag.standard}, 'H2');
      // #endregion

      if (tag.type != NFCTagType.iso7816 && 
          tag.type != NFCTagType.mifare_desfire && 
          tag.type != NFCTagType.iso15693 &&
          tag.type != NFCTagType.mifare_classic &&
          tag.type != NFCTagType.mifare_ultralight) {
        // #region agent log
        DebugLogger.log('nfc_service.dart:38', 'Unsupported tag type detected', {'tagType': tag.type.toString()}, 'H2');
        // #endregion
        await FlutterNfcKit.finish(iosAlertMessage: "Unsupported card type");
        throw Exception('Unsupported card type: ${tag.type}');
      }
      
      if (tag.type == NFCTagType.mifare_classic || tag.type == NFCTagType.mifare_ultralight) {
        // #region agent log
        DebugLogger.log('nfc_service.dart:39', 'MIFARE card detected, not a payment card', {'tagType': tag.type.toString()}, 'H2');
        // #endregion
        await FlutterNfcKit.finish(iosAlertMessage: "Not a payment card");
        throw Exception('This appears to be a MIFARE access card, not a payment card.');
      }

      String? selectResponse;
      List<String> aids = [];
      bool ppseSucceeded = false;
      
      try {
        String ppseResponse = await _selectPPSE();
        // #region agent log
        DebugLogger.log('nfc_service.dart:42', 'PPSE selected successfully', {'response': ppseResponse}, 'H3');
        // #endregion
        ppseSucceeded = true;
        
        aids = await _extractAIDs(ppseResponse);
        // #region agent log
        DebugLogger.log('nfc_service.dart:44', 'AIDs extracted', {'count': aids.length, 'aids': aids}, 'H4');
        // #endregion
      } catch (e) {
        // #region agent log
        DebugLogger.log('nfc_service.dart:43', 'PPSE failed, will try known AIDs directly', {'error': e.toString()}, 'H3');
        // #endregion
      }
      
      if (aids.isNotEmpty) {
        for (String aid in aids) {
          try {
            // #region agent log
            DebugLogger.log('nfc_service.dart:45', 'Trying AID from PPSE', {'aid': aid}, 'H4');
            // #endregion
            selectResponse = await _selectApplication(aid);
            // #region agent log
            DebugLogger.log('nfc_service.dart:46', 'Application selected successfully', {'aid': aid}, 'H4');
            // #endregion
            break;
          } catch (e) {
            // #region agent log
            DebugLogger.log('nfc_service.dart:47', 'AID selection failed, trying next', {'aid': aid, 'error': e.toString()}, 'H4');
            // #endregion
            continue;
          }
        }
      }
      
      if (selectResponse == null) {
        // #region agent log
        DebugLogger.log('nfc_service.dart:48', 'No AID from PPSE worked, trying known AIDs', {'ppseSucceeded': ppseSucceeded}, 'H4');
        // #endregion
        selectResponse = await _tryKnownAIDs();
      }
      
      String gpoResponse = await _getProcessingOptions(selectResponse);
      // #region agent log
      DebugLogger.log('nfc_service.dart:48', 'GPO completed', {'gpoResponse': gpoResponse}, 'H5');
      // #endregion
      
      CardData cardData = await _readRecords(gpoResponse);
      // #region agent log
      DebugLogger.log('nfc_service.dart:50', 'Card data read successfully', {'cardType': cardData.cardType}, 'H6');
      // #endregion

      await FlutterNfcKit.finish(iosAlertMessage: "Card read successfully");
      
      return cardData;
    } catch (e) {
      // #region agent log
      DebugLogger.log('nfc_service.dart:55', 'readCard exception', {'error': e.toString(), 'stackTrace': e is Error ? e.stackTrace.toString() : 'N/A'}, 'H2');
      // #endregion
      
      String errorMessage = "Error reading card";
      if (e.toString().contains('All known AIDs failed')) {
        errorMessage = "Card detected but no payment application found. This card may not support NFC reading.";
      } else if (e.toString().contains('6985')) {
        errorMessage = "This card has NFC reading restrictions. Please use Camera Scan or Manual Entry instead.";
      } else if (e.toString().contains('PPSE') || e.toString().contains('AID')) {
        errorMessage = "Unable to communicate with card. Please try again or use camera scan.";
      } else if (e.toString().contains('Failed to read card records')) {
        errorMessage = "Card found but couldn't read data. Try camera or manual entry.";
      }
      
      try {
        await FlutterNfcKit.finish(iosAlertMessage: errorMessage);
      } catch (_) {}
      rethrow;
    }
  }

  Future<String> _selectPPSE() async {
    try {
      // #region agent log
      DebugLogger.log('nfc_service.dart:63', 'Sending PPSE select command', {'command': ApduCommands.selectPpse}, 'H3');
      // #endregion
      String response = await _transceiveWithRetry(ApduCommands.selectPpse);
      // #region agent log
      DebugLogger.log('nfc_service.dart:65', 'PPSE response received', {'response': response, 'length': response.length}, 'H3');
      // #endregion
      
      if (response.length < 4) {
        throw Exception('Invalid PPSE response: too short');
      }

      String sw1sw2 = response.substring(response.length - 4);
      // #region agent log
      DebugLogger.log('nfc_service.dart:71', 'PPSE status word', {'sw1sw2': sw1sw2}, 'H3');
      // #endregion
      if (sw1sw2 != '9000') {
        throw Exception('PPSE selection failed with status: $sw1sw2');
      }

      return response;
    } catch (e) {
      // #region agent log
      DebugLogger.log('nfc_service.dart:77', 'PPSE selection exception', {'error': e.toString()}, 'H3');
      // #endregion
      rethrow;
    }
  }

  Future<List<String>> _extractAIDs(String ppseResponse) async {
    List<String> aids = [];
    try {
      // #region agent log
      DebugLogger.log('nfc_service.dart:82', 'Extracting AIDs from PPSE', {}, 'H4');
      // #endregion
      List<int> responseBytes = HexUtils.hexToBytes(ppseResponse.substring(0, ppseResponse.length - 4));
      
      Map<String, dynamic> tlvData = TLVParser.parse(responseBytes);
      // #region agent log
      DebugLogger.log('nfc_service.dart:86', 'TLV parsed', {'tags': tlvData.keys.toList()}, 'H4');
      // #endregion
      
      List<int>? fciTemplate = TLVParser.findTagBytes(tlvData, '6F');
      if (fciTemplate == null) {
        throw Exception('FCI template not found in PPSE response');
      }

      Map<String, dynamic> fciData = TLVParser.parse(fciTemplate);
      
      List<int>? fciProprietaryTemplate = TLVParser.findTagBytes(fciData, 'A5');
      if (fciProprietaryTemplate == null) {
        throw Exception('FCI Proprietary Template not found');
      }

      Map<String, dynamic> proprietaryData = TLVParser.parse(fciProprietaryTemplate);
      
      List<int>? fciIssuerDiscretionaryData = TLVParser.findTagBytes(proprietaryData, 'BF0C');
      if (fciIssuerDiscretionaryData == null) {
        throw Exception('FCI Issuer Discretionary Data not found');
      }

      List<int> discretionaryBytes = fciIssuerDiscretionaryData;
      int index = 0;
      
      while (index < discretionaryBytes.length) {
        if (index >= discretionaryBytes.length) break;
        
        if (discretionaryBytes[index] == 0x61) {
          index++;
          if (index >= discretionaryBytes.length) break;
          
          int length = discretionaryBytes[index];
          index++;
          
          if (index + length > discretionaryBytes.length) break;
          
          List<int> applicationTemplate = discretionaryBytes.sublist(index, index + length);
          Map<String, dynamic> appData = TLVParser.parse(applicationTemplate);
          
          String? aid = TLVParser.findTag(appData, '4F');
          if (aid != null && aid.isNotEmpty) {
            aids.add(aid);
            // #region agent log
            DebugLogger.log('nfc_service.dart:116', 'AID found', {'aid': aid}, 'H4');
            // #endregion
          }
          
          index += length;
        } else {
          index++;
        }
      }
      
      if (aids.isEmpty) {
        throw Exception('No AIDs found in application templates');
      }
      
      // #region agent log
      DebugLogger.log('nfc_service.dart:120', 'All AIDs extracted', {'count': aids.length, 'aids': aids}, 'H4');
      // #endregion

      return aids;
    } catch (e) {
      // #region agent log
      DebugLogger.log('nfc_service.dart:122', 'AID extraction exception', {'error': e.toString()}, 'H4');
      // #endregion
      throw Exception('Failed to extract AIDs: $e');
    }
  }

  Future<String> _selectApplication(String aid) async {
    try {
      String selectAidCommand = ApduCommands.selectAID(aid);
      // #region agent log
      DebugLogger.log('nfc_service.dart:127', 'Selecting application', {'aid': aid, 'command': selectAidCommand}, 'H4');
      // #endregion
      
      String response = await _transceiveWithRetry(selectAidCommand);
      // #region agent log
      DebugLogger.log('nfc_service.dart:131', 'Application selection response', {'response': response, 'length': response.length}, 'H4');
      // #endregion
      
      if (response.length < 4) {
        throw Exception('Invalid AID selection response: too short (${response.length} chars)');
      }

      String sw1sw2 = response.substring(response.length - 4);
      // #region agent log
      DebugLogger.log('nfc_service.dart:135', 'AID selection status', {'sw1sw2': sw1sw2, 'aid': aid}, 'H4');
      // #endregion
      
      if (sw1sw2 != '9000') {
        throw Exception('AID selection failed with status: $sw1sw2 (aid: $aid)');
      }
      
      return response;
    } catch (e) {
      // #region agent log
      DebugLogger.log('nfc_service.dart:141', 'Application selection exception', {'aid': aid, 'error': e.toString()}, 'H4');
      // #endregion
      rethrow;
    }
  }

  Future<String> _tryKnownAIDs() async {
    final List<Map<String, String>> knownAIDs = [
      // Try AMEX first with comprehensive AID list (India & International)
      {'name': 'American Express', 'aid': 'A000000025'},            // Base (shortest, try first)
      {'name': 'American Express', 'aid': 'A00000002501'},          // Primary
      {'name': 'American Express India', 'aid': 'A000000025010104'}, // India Credit
      {'name': 'American Express India', 'aid': 'A000000025010701'}, // India Debit
      {'name': 'American Express India', 'aid': 'A000000025010801'}, // India Prepaid
      {'name': 'American Express', 'aid': 'A000000025010103'},      // Europe
      {'name': 'American Express', 'aid': 'A000000025010105'},      // Asia Pacific
      {'name': 'American Express', 'aid': 'A000000025010106'},      // UK
      {'name': 'American Express', 'aid': 'A000000025010108'},      // Canada
      {'name': 'American Express', 'aid': 'A0000000250000'},        // International
      {'name': 'American Express', 'aid': 'A00000002501010102'},    // Specific variant
      {'name': 'American Express', 'aid': 'A00000002501'},          // Alternative format
      {'name': 'American Express', 'aid': 'A0000000250100'},        // Legacy format
      {'name': 'American Express', 'aid': 'A000000025010102'},      // Additional variant
      // Then Visa
      {'name': 'Visa Credit/Debit', 'aid': 'A0000000031010'},
      {'name': 'Visa Electron', 'aid': 'A0000000032010'},
      {'name': 'Visa Interlink', 'aid': 'A0000000033010'},
      {'name': 'Visa V Pay', 'aid': 'A0000000032020'},
      {'name': 'Visa Plus', 'aid': 'A0000000038010'},
      {'name': 'Visa Platinum', 'aid': 'A0000000030000'},
      // Mastercard
      {'name': 'Mastercard Credit/Debit', 'aid': 'A0000000041010'},
      {'name': 'Maestro', 'aid': 'A0000000043060'},
      {'name': 'Mastercard Debit', 'aid': 'A00000000410101213'},
      {'name': 'Mastercard Credit', 'aid': 'A00000000410101215'},
      // Other networks
      {'name': 'Discover', 'aid': 'A0000001523010'},
      {'name': 'Discover', 'aid': 'A0000003241010'},
      {'name': 'JCB', 'aid': 'A0000000651010'},
      {'name': 'UnionPay', 'aid': 'A000000333010101'},
      {'name': 'UnionPay', 'aid': 'A000000333010102'},
      {'name': 'UnionPay Debit', 'aid': 'A000000333010103'},
      {'name': 'RuPay', 'aid': 'A0000005241010'},
      {'name': 'RuPay Domestic', 'aid': 'A000000524'},
      {'name': 'RuPay Credit', 'aid': 'A0000005240010'},
      {'name': 'Diners Club', 'aid': 'A0000001523010'},
    ];

    // #region agent log
    DebugLogger.log('nfc_service.dart:tryKnownAIDs', 'Trying known payment AIDs', {'count': knownAIDs.length}, 'H4');
    // #endregion

    for (var aidInfo in knownAIDs) {
      try {
        // #region agent log
        DebugLogger.log('nfc_service.dart:tryKnownAIDs', 'Trying known AID', {'name': aidInfo['name'], 'aid': aidInfo['aid']}, 'H4');
        // #endregion
        
        String response = await _selectApplication(aidInfo['aid']!);
        
        // #region agent log
        DebugLogger.log('nfc_service.dart:tryKnownAIDs', 'Known AID succeeded', {'name': aidInfo['name'], 'aid': aidInfo['aid']}, 'H4');
        // #endregion
        
        return response;
      } catch (e) {
        // #region agent log
        DebugLogger.log('nfc_service.dart:tryKnownAIDs', 'Known AID failed', {'name': aidInfo['name'], 'error': e.toString()}, 'H4');
        // #endregion
        continue;
      }
    }

    throw Exception('All known AIDs failed. Card may not be supported.');
  }

  String _buildGPOCommand(String selectResponse) {
    try {
      List<int> responseBytes = HexUtils.hexToBytes(selectResponse.substring(0, selectResponse.length - 4));
      Map<String, dynamic> fciData = TLVParser.parse(responseBytes);
      
      List<int>? fciTemplate = TLVParser.findTagBytes(fciData, '6F');
      if (fciTemplate != null) {
        Map<String, dynamic> fciParsed = TLVParser.parse(fciTemplate);
        List<int>? a5Template = TLVParser.findTagBytes(fciParsed, 'A5');
        
        if (a5Template != null) {
          Map<String, dynamic> a5Parsed = TLVParser.parse(a5Template);
          List<int>? pdol = TLVParser.findTagBytes(a5Parsed, '9F38');
          
          if (pdol != null && pdol.isNotEmpty) {
            // #region agent log
            DebugLogger.log('nfc_service.dart:_buildGPOCommand', 'PDOL found', {'pdolHex': HexUtils.bytesToHex(pdol), 'length': pdol.length}, 'H5');
            // #endregion
            
            List<int> pdolData = _buildPDOLData(pdol);
            String pdolDataHex = HexUtils.bytesToHex(pdolData);
            int pdolDataLength = pdolData.length;
            String pdolLengthHex = pdolDataLength.toRadixString(16).padLeft(2, '0');
            int totalLength = pdolDataLength + 2;
            String totalLengthHex = totalLength.toRadixString(16).padLeft(2, '0');
            
            String gpoCmd = "80A80000${totalLengthHex}83${pdolLengthHex}${pdolDataHex}00";
            // #region agent log
            DebugLogger.log('nfc_service.dart:_buildGPOCommand', 'Built GPO with PDOL', {'command': gpoCmd, 'pdolDataLength': pdolDataLength, 'totalLength': totalLength}, 'H5');
            // #endregion
            return gpoCmd;
          }
        }
      }
      
      // #region agent log
      DebugLogger.log('nfc_service.dart:_buildGPOCommand', 'No PDOL found, using default GPO', {}, 'H5');
      // #endregion
      return ApduCommands.gpoCommand;
    } catch (e) {
      // #region agent log
      DebugLogger.log('nfc_service.dart:_buildGPOCommand', 'Error building GPO, using default', {'error': e.toString()}, 'H5');
      // #endregion
      return ApduCommands.gpoCommand;
    }
  }
  
  List<int> _buildPDOLData(List<int> pdol) {
    List<int> pdolData = [];
    int index = 0;
    List<Map<String, dynamic>> pdolTags = [];
    
    while (index < pdol.length) {
      String tag = '';
      int tagByte = pdol[index];
      tag = tagByte.toRadixString(16).padLeft(2, '0').toUpperCase();
      index++;
      
      if ((tagByte & 0x1F) == 0x1F && index < pdol.length) {
        tag += pdol[index].toRadixString(16).padLeft(2, '0').toUpperCase();
        index++;
      }
      
      if (index >= pdol.length) break;
      
      int length = pdol[index];
      index++;
      
      List<int> defaultValue = _getDefaultPDOLValue(tag, length);
      pdolData.addAll(defaultValue);
      
      pdolTags.add({
        'tag': tag,
        'length': length,
        'value': HexUtils.bytesToHex(defaultValue)
      });
    }
    
    // #region agent log
    DebugLogger.log('nfc_service.dart:_buildPDOLData', 'PDOL data built', 
      {'tags': pdolTags, 'totalLength': pdolData.length}, 'H5');
    // #endregion
    
    return pdolData;
  }
  
  List<int> _getDefaultPDOLValue(String tag, int length) {
    switch (tag) {
      case '9F66':
        if (length == 4) return [0xB6, 0x20, 0xC0, 0x00];
        return List.filled(length, 0x00);
      case '9F02':
        if (length == 6) return [0x00, 0x00, 0x00, 0x00, 0x00, 0x01];
        return List.filled(length, 0x00);
      case '9F03':
        return List.filled(length, 0x00);
      case '9F1A':
        if (length == 2) return [0x03, 0x56];
        return List.filled(length, 0x00);
      case '95':
        if (length == 5) return [0x00, 0x00, 0x00, 0x00, 0x00];
        return List.filled(length, 0x00);
      case '5F2A':
        if (length == 2) return [0x03, 0x56];
        return List.filled(length, 0x00);
      case '9A':
        DateTime now = DateTime.now();
        String year = (now.year % 100).toString().padLeft(2, '0');
        String month = now.month.toString().padLeft(2, '0');
        String day = now.day.toString().padLeft(2, '0');
        String dateStr = year + month + day;
        return HexUtils.hexToBytes(dateStr);
      case '9C':
        if (length == 1) return [0x00];
        return List.filled(length, 0x00);
      case '9F37':
        if (length == 4) {
          int random = DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFF;
          return [
            (random >> 24) & 0xFF,
            (random >> 16) & 0xFF,
            (random >> 8) & 0xFF,
            random & 0xFF,
          ];
        }
        return List.filled(length, 0x00);
      case '9F40':
        if (length == 5) return [0xF0, 0x00, 0xF0, 0xA0, 0x01];
        return List.filled(length, 0x00);
      case 'DF3A':
        if (length == 5) return [0x00, 0x00, 0x00, 0x00, 0x00];
        return List.filled(length, 0x00);
      case '9F33':
        if (length == 3) return [0xE0, 0xF8, 0xC8];
        return List.filled(length, 0x00);
      case '9F09':
        if (length == 2) return [0x00, 0x02];
        return List.filled(length, 0x00);
      case '9F15':
        if (length == 2) return [0x52, 0x75];
        return List.filled(length, 0x00);
      case '9F21':
        if (length == 3) {
          DateTime now = DateTime.now();
          String hour = now.hour.toString().padLeft(2, '0');
          String minute = now.minute.toString().padLeft(2, '0');
          String second = now.second.toString().padLeft(2, '0');
          String timeStr = hour + minute + second;
          return HexUtils.hexToBytes(timeStr);
        }
        return List.filled(length, 0x00);
      case 'DF16':
        if (length == 2) return [0x00, 0x00];
        return List.filled(length, 0x00);
      case '9F1C':
        if (length == 8) return [0x38, 0x32, 0x33, 0x30, 0x30, 0x30, 0x30, 0x30];
        return List.filled(length, 0x00);
      case '9F35':
        // Terminal Type - critical for AMEX
        // Try multiple values in sequence: 0x22 (online capable merchant terminal)
        if (length == 1) return [0x22];
        return List.filled(length, 0x00);
      case '9F6E':
        // Form Factor Indicator (Device Type) - critical for AMEX  
        // AMEX India specific: Try consumer device with contactless
        // Byte 1: 0x02 = Consumer Device (smartphone/tablet)
        // Byte 2: 0x00 = Standard
        // Byte 3: 0x00 = Standard reader
        // Byte 4: 0x00 = Reserved
        if (length == 4) return [0x02, 0x00, 0x00, 0x00];
        return List.filled(length, 0x00);
      case '9F7C':
        // Merchant Custom Data - sometimes required by AMEX
        if (length == 14) return List.filled(length, 0x00);
        return List.filled(length, 0x00);
      default:
        return List.filled(length, 0x00);
    }
  }

  Future<String> _getProcessingOptions(String selectResponse) async {
    try {
      String gpoCommand = _buildGPOCommand(selectResponse);
      // #region agent log
      DebugLogger.log('nfc_service.dart:146', 'Sending GPO command', {'command': gpoCommand}, 'H5');
      // #endregion
      String response = await _transceiveWithRetry(gpoCommand);
      // #region agent log
      DebugLogger.log('nfc_service.dart:148', 'GPO response received', {'response': response, 'length': response.length}, 'H5');
      // #endregion
      
      if (response.length < 4) {
        throw Exception('Invalid GPO response: too short');
      }

      String sw1sw2 = response.substring(response.length - 4);
      
      // If GPO failed with 6985 (conditions not satisfied), try simple GPO for AMEX
      if (sw1sw2 == '6985') {
        // #region agent log
        DebugLogger.log('nfc_service.dart:149', 'GPO rejected (6985), trying simple GPO', {}, 'H5');
        // #endregion
        
        // Try the simplest possible GPO command (no PDOL data)
        response = await _transceiveWithRetry(ApduCommands.gpoCommand);
        sw1sw2 = response.substring(response.length - 4);
        
        // #region agent log
        DebugLogger.log('nfc_service.dart:150', 'Simple GPO response', {'response': response, 'sw1sw2': sw1sw2}, 'H5');
        // #endregion
      }
      
      if (sw1sw2 != '9000') {
        throw Exception('GPO failed with status: $sw1sw2');
      }

      List<int> responseBytes = HexUtils.hexToBytes(response.substring(0, response.length - 4));
      
      Map<String, dynamic> tlvData = TLVParser.parse(responseBytes);
      // #region agent log
      DebugLogger.log('nfc_service.dart:161', 'GPO TLV parsed', {'tags': tlvData.keys.toList()}, 'H5');
      // #endregion
      
      List<int>? aflData = TLVParser.findTagBytes(tlvData, '94');
      
      if (aflData == null) {
        List<int>? responseFormat2 = TLVParser.findTagBytes(tlvData, '77');
        if (responseFormat2 != null) {
          Map<String, dynamic> format2Data = TLVParser.parse(responseFormat2);
          aflData = TLVParser.findTagBytes(format2Data, '94');
        }
      }

      if (aflData == null || aflData.isEmpty) {
        // #region agent log
        DebugLogger.log('nfc_service.dart:173', 'AFL not found in GPO', {}, 'H5');
        // #endregion
        throw Exception('AFL (Application File Locator) not found in GPO response');
      }
      
      final List<int> aflDataFinal = aflData;
      // #region agent log
      DebugLogger.log('nfc_service.dart:176', 'AFL found', {'aflLength': aflDataFinal.length, 'aflHex': HexUtils.bytesToHex(aflDataFinal)}, 'H5');
      // #endregion

      return response;
    } catch (e) {
      // #region agent log
      DebugLogger.log('nfc_service.dart:179', 'GPO exception', {'error': e.toString()}, 'H5');
      // #endregion
      throw Exception('Failed to get processing options: $e');
    }
  }

  Future<CardData> _readRecords(String gpoResponse) async {
    String? pan;
    String? expiryDate;
    String? cardholderName;

    try {
      // First, try to extract data from GPO response
      List<int> gpoBytes = HexUtils.hexToBytes(gpoResponse.substring(0, gpoResponse.length - 4));
      Map<String, dynamic> gpoTlv = TLVParser.parse(gpoBytes);
      
      // #region agent log
      DebugLogger.log('nfc_service.dart:183', 'Parsing GPO response for card data', {'tags': gpoTlv.keys.toList()}, 'H6');
      // #endregion
      
      // Check if GPO response contains card data directly
      List<int>? responseTemplate = TLVParser.findTagBytes(gpoTlv, '77');
      if (responseTemplate != null) {
        Map<String, dynamic> responseTlv = TLVParser.parse(responseTemplate);
        pan = _extractPAN(responseTlv);
        expiryDate = _extractExpiry(responseTlv);
        cardholderName = _extractCardholderName(responseTlv);
        
        // #region agent log
        DebugLogger.log('nfc_service.dart:195', 'Extracted from GPO response', {'hasPAN': pan != null, 'hasExpiry': expiryDate != null, 'hasName': cardholderName != null}, 'H6');
        // #endregion
      }
      
      // If we have all required data, return early
      if (pan != null && expiryDate != null) {
        // #region agent log
        DebugLogger.log('nfc_service.dart:200', 'Card data found in GPO response, skipping record reading', {}, 'H6');
        // #endregion
        
        String cardType = _determineCardType(pan);
        return await CardData.fromPlaintext(
          cardNumber: pan,
          expiryDate: expiryDate,
          cardholderName: cardholderName,
          cardType: cardType,
        );
      }
      
      // Extract AFL for reading records
      List<int>? aflData = TLVParser.findTagBytes(gpoTlv, '94');
      if (aflData == null && responseTemplate != null) {
        Map<String, dynamic> responseTlv = TLVParser.parse(responseTemplate);
        aflData = TLVParser.findTagBytes(responseTlv, '94');
      }
      
      if (aflData == null || aflData.isEmpty) {
        // #region agent log
        DebugLogger.log('nfc_service.dart:220', 'No AFL found and no data in GPO', {}, 'H6');
        // #endregion
        throw Exception('No card data found in GPO response and no AFL to read records');
      }
      
      // #region agent log
      DebugLogger.log('nfc_service.dart:225', 'Starting to read records from AFL', {'aflLength': aflData.length}, 'H6');
      // #endregion
      
      for (int i = 0; i < aflData.length; i += 4) {
        if (i + 3 >= aflData.length) break;

        int sfi = (aflData[i] >> 3) & 0x1F;
        int firstRecord = aflData[i + 1];
        int lastRecord = aflData[i + 2];
        // #region agent log
        DebugLogger.log('nfc_service.dart:192', 'Processing AFL entry', {'sfi': sfi, 'firstRecord': firstRecord, 'lastRecord': lastRecord}, 'H6');
        // #endregion

        for (int recordNum = firstRecord; recordNum <= lastRecord; recordNum++) {
          try {
            String readRecordCommand = ApduCommands.readRecord(recordNum, sfi);
            // #region agent log
            DebugLogger.log('nfc_service.dart:197', 'Reading record', {'recordNum': recordNum, 'sfi': sfi, 'command': readRecordCommand}, 'H6');
            // #endregion
            String response = await _transceiveWithRetry(readRecordCommand, maxRetries: 2);

            if (response.length < 4) continue;

            String sw1sw2 = response.substring(response.length - 4);
            if (sw1sw2 != '9000') continue;

            List<int> recordData = HexUtils.hexToBytes(response.substring(0, response.length - 4));
            
            Map<String, dynamic> recordTlv = TLVParser.parse(recordData);
            // #region agent log
            DebugLogger.log('nfc_service.dart:208', 'Record parsed', {'tags': recordTlv.keys.toList()}, 'H6');
            // #endregion

            pan ??= _extractPAN(recordTlv);
            // #region agent log
            if (pan != null) {
              DebugLogger.log('nfc_service.dart:210', 'PAN extracted from record', {'sfi': sfi, 'recordNum': recordNum}, 'H6');
            }
            // #endregion

            expiryDate ??= _extractExpiry(recordTlv);
            // #region agent log
            if (expiryDate != null) {
              DebugLogger.log('nfc_service.dart:212', 'Expiry extracted from record', {'sfi': sfi, 'recordNum': recordNum}, 'H6');
            }
            // #endregion

            cardholderName ??= _extractCardholderName(recordTlv);

            if (pan != null && expiryDate != null) {
              // #region agent log
              DebugLogger.log('nfc_service.dart:215', 'Found all required data, stopping record read', {'sfi': sfi, 'recordNum': recordNum}, 'H6');
              // #endregion
              break;
            }
          } catch (e) {
            // #region agent log
            DebugLogger.log('nfc_service.dart:218', 'Record read failed, continuing', {'sfi': sfi, 'recordNum': recordNum, 'error': e.toString()}, 'H6');
            // #endregion
            
            if (e.toString().contains('Tag was lost') || e.toString().contains('TagLostException')) {
              // #region agent log
              DebugLogger.log('nfc_service.dart:220', 'Tag lost, checking if we have enough data', {'hasPAN': pan != null, 'hasExpiry': expiryDate != null}, 'H6');
              // #endregion
              if (pan != null && expiryDate != null) {
                break;
              }
            }
            continue;
          }
        }

        if (pan != null && expiryDate != null) {
          // #region agent log
          DebugLogger.log('nfc_service.dart:223', 'Breaking AFL loop, all data found', {}, 'H6');
          // #endregion
          break;
        }
      }

      if (pan == null) {
        // #region agent log
        DebugLogger.log('nfc_service.dart:229', 'PAN not found after reading all available records', {'recordsAttempted': 'multiple'}, 'H6');
        // #endregion
        throw Exception('Card number (PAN) not found on card. Card may have been removed too early or data may be encrypted.');
      }

      if (expiryDate == null) {
        // #region agent log
        DebugLogger.log('nfc_service.dart:234', 'Expiry date not found', {}, 'H6');
        // #endregion
        throw Exception('Expiry date not found on card');
      }
      // #region agent log
      DebugLogger.log('nfc_service.dart:237', 'Card data extracted successfully', {'hasName': cardholderName != null}, 'H6');
      // #endregion

      String cardType = _determineCardType(pan);

      return await CardData.fromPlaintext(
        cardNumber: pan,
        expiryDate: expiryDate,
        cardholderName: cardholderName,
        cardType: cardType,
      );
    } catch (e) {
      // #region agent log
      DebugLogger.log('nfc_service.dart:252', 'Read records exception', {'error': e.toString()}, 'H6');
      // #endregion
      throw Exception('Failed to read card records: $e');
    }
  }

  String? _extractPAN(Map<String, dynamic> tlvData) {
    List<int>? panBytes = TLVParser.findTagBytes(tlvData, '5A');
    
    if (panBytes == null) {
      List<int>? template70 = TLVParser.findTagBytes(tlvData, '70');
      if (template70 != null) {
        try {
          Map<String, dynamic> nestedTlv = TLVParser.parse(template70);
          panBytes = TLVParser.findTagBytes(nestedTlv, '5A');
          if (panBytes == null) {
            List<int>? track2Bytes = TLVParser.findTagBytes(nestedTlv, '57');
            if (track2Bytes != null) {
              String track2Hex = HexUtils.bytesToHex(track2Bytes);
              int separatorIndex = track2Hex.indexOf('D');
              if (separatorIndex == -1) separatorIndex = track2Hex.indexOf('=');
              if (separatorIndex != -1) {
                String panHex = track2Hex.substring(0, separatorIndex);
                return HexUtils.cleanPAN(panHex);
              }
            }
          }
        } catch (e) {
          // Continue to check track2 at top level
        }
      }
      
      if (panBytes == null) {
        List<int>? track2Bytes = TLVParser.findTagBytes(tlvData, '57');
        if (track2Bytes != null) {
          String track2Hex = HexUtils.bytesToHex(track2Bytes);
          
          int separatorIndex = track2Hex.indexOf('D');
          if (separatorIndex == -1) {
            separatorIndex = track2Hex.indexOf('=');
          }
          
          if (separatorIndex != -1) {
            String panHex = track2Hex.substring(0, separatorIndex);
            String pan = HexUtils.cleanPAN(panHex);
            
            return pan;
          }
        }
        return null;
      }
    }

    String panHex = HexUtils.bytesToHex(panBytes);
    String pan = HexUtils.cleanPAN(panHex);
    
    return pan;
  }

  String? _extractExpiry(Map<String, dynamic> tlvData) {
    List<int>? expiryBytes = TLVParser.findTagBytes(tlvData, '5F24');
    
    if (expiryBytes == null) {
      List<int>? template70 = TLVParser.findTagBytes(tlvData, '70');
      if (template70 != null) {
        try {
          Map<String, dynamic> nestedTlv = TLVParser.parse(template70);
          expiryBytes = TLVParser.findTagBytes(nestedTlv, '5F24');
          if (expiryBytes == null) {
            List<int>? track2Bytes = TLVParser.findTagBytes(nestedTlv, '57');
            if (track2Bytes != null) {
              String track2Hex = HexUtils.bytesToHex(track2Bytes);
              int separatorIndex = track2Hex.indexOf('D');
              if (separatorIndex == -1) separatorIndex = track2Hex.indexOf('=');
              if (separatorIndex != -1 && separatorIndex + 4 < track2Hex.length) {
                String expiryYYMM = track2Hex.substring(separatorIndex + 1, separatorIndex + 5);
                return HexUtils.formatExpiry(expiryYYMM);
              }
            }
          }
        } catch (e) {
          // Continue to check track2 at top level
        }
      }
      
      if (expiryBytes == null) {
        List<int>? track2Bytes = TLVParser.findTagBytes(tlvData, '57');
        if (track2Bytes != null) {
          String track2Hex = HexUtils.bytesToHex(track2Bytes);
          
          int separatorIndex = track2Hex.indexOf('D');
          if (separatorIndex == -1) {
            separatorIndex = track2Hex.indexOf('=');
          }
          
          if (separatorIndex != -1 && separatorIndex + 4 < track2Hex.length) {
            String expiryYYMM = track2Hex.substring(separatorIndex + 1, separatorIndex + 5);
            String formattedExpiry = HexUtils.formatExpiry(expiryYYMM);
            
            return formattedExpiry;
          }
        }
        return null;
      }
    }

    String expiryHex = HexUtils.bytesToHex(expiryBytes);
    
    if (expiryHex.length >= 4) {
      String expiryYYMM = expiryHex.substring(0, 4);
      String formattedExpiry = HexUtils.formatExpiry(expiryYYMM);
      
      return formattedExpiry;
    }

    return null;
  }

  String? _extractCardholderName(Map<String, dynamic> tlvData) {
    List<int>? nameBytes = TLVParser.findTagBytes(tlvData, '5F20');
    
    if (nameBytes == null) {
      List<int>? template70 = TLVParser.findTagBytes(tlvData, '70');
      if (template70 != null) {
        try {
          Map<String, dynamic> nestedTlv = TLVParser.parse(template70);
          nameBytes = TLVParser.findTagBytes(nestedTlv, '5F20');
        } catch (e) {
          // Name not found in nested structure
        }
      }
    }
    
    if (nameBytes == null) {
      return null;
    }

    try {
      String name = String.fromCharCodes(nameBytes).trim();
      if (name.isEmpty || name == '/') {
        return null;
      }
      return name;
    } catch (e) {
      return null;
    }
  }

  String _determineCardType(String pan) =>
      CardNetworkUtils.cardTypeFromNumber(pan);
}


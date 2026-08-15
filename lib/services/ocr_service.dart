import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:image/image.dart' as img;
import '../utils/image_utils.dart';
import '../utils/card_network_utils.dart';
import 'card_ocr_model.dart';

class OCRResult {
  final String? cardNumber;
  final String? expiryDate;
  final String? cardholderName;
  final String? cardType;

  OCRResult({
    this.cardNumber,
    this.expiryDate,
    this.cardholderName,
    this.cardType,
  });
}

class OCRService {
  final TextRecognizer _textRecognizer = TextRecognizer();
  final CardOCRModel _cardModel = CardOCRModel();

  Future<OCRResult> processImage(String imagePath, {bool preprocess = true}) async {
    try {
      print('=== OCR PROCESSING START ===');
      
      String? cardNumber;
      String? expiryDate;
      String? cardholderName;
      
      print('\n--- ATTEMPT 1: Region-Based OCR (AI Model) ---');
      Map<String, dynamic> regionResult = await _cardModel.detectCardRegions(imagePath);
      
      if (regionResult['success'] == true) {
        Map<String, img.Image> regions = regionResult['croppedImages'];
        
        if (regions.containsKey('cardNumber') && regions['cardNumber'] != null) {
          img.Image processedCardNum = _cardModel.preprocessRegion(
            regions['cardNumber']!,
            forNumbers: true,
          );
          String cardNumPath = await _cardModel.saveRegionImage(
            processedCardNum,
            imagePath,
            'cardnum',
          );
          
          try {
            String cardNumText = await FlutterTesseractOcr.extractText(
              cardNumPath,
              language: 'eng',
              args: {
                "psm": "7",
                "tessedit_char_whitelist": "0123456789 ",
              },
            );
            print('Card number region text: $cardNumText');
            List<TextBlock> emptyBlocks = [];
            cardNumber = _extractCardNumber(cardNumText, emptyBlocks);
          } catch (e) {
            print('Card number region OCR failed: $e');
          }
        }

        if (expiryDate == null && regions.containsKey('expiry')) {
          img.Image processedExpiry = _cardModel.preprocessRegion(
            regions['expiry']!,
            forNumbers: true,
          );
          String expiryPath = await _cardModel.saveRegionImage(
            processedExpiry,
            imagePath,
            'expiry',
          );
          
          try {
            String expiryText = await FlutterTesseractOcr.extractText(
              expiryPath,
              language: 'eng',
              args: {
                "psm": "7",
                "tessedit_char_whitelist": "0123456789/",
              },
            );
            print('Expiry region text: $expiryText');
            List<TextBlock> emptyBlocks = [];
            expiryDate = _extractExpiryDate(expiryText, emptyBlocks);
          } catch (e) {
            print('Expiry region OCR failed: $e');
          }
        }

        if (cardholderName == null && regions.containsKey('name')) {
          img.Image processedName = _cardModel.preprocessRegion(
            regions['name']!,
            forNumbers: false,
          );
          String namePath = await _cardModel.saveRegionImage(
            processedName,
            imagePath,
            'name',
          );
          
          try {
            String nameText = await FlutterTesseractOcr.extractText(
              namePath,
              language: 'eng',
              args: {
                "psm": "7",
              },
            );
            print('Name region text: $nameText');
            List<TextBlock> emptyBlocks = [];
            cardholderName = _extractCardholderName(nameText, emptyBlocks);
          } catch (e) {
            print('Name region OCR failed: $e');
          }
        }
      }
      
      print('Region-based results - Card: $cardNumber, Expiry: $expiryDate, Name: $cardholderName');

      if (cardNumber == null) {
        print('\n--- ATTEMPT 2: ML Kit on Original ---');
        final originalImage = InputImage.fromFile(File(imagePath));
        final mlKitText = await _textRecognizer.processImage(originalImage);
        
        print('ML Kit text: ${mlKitText.text}');
        print('ML Kit blocks: ${mlKitText.blocks.length}');
        
        cardNumber = _extractCardNumber(mlKitText.text, mlKitText.blocks);
        expiryDate = expiryDate ?? _extractExpiryDate(mlKitText.text, mlKitText.blocks);
        cardholderName = cardholderName ?? _extractCardholderName(mlKitText.text, mlKitText.blocks);
        
        print('ML Kit results - Card: $cardNumber, Expiry: $expiryDate, Name: $cardholderName');
      }

      if (cardNumber == null) {
        print('\n--- ATTEMPT 3: Tesseract Full Image ---');
        try {
          String tesseractText = await FlutterTesseractOcr.extractText(
            imagePath,
            language: 'eng',
            args: {
              "psm": "6",
              "preserve_interword_spaces": "1",
            },
          );
          
          print('Tesseract text: $tesseractText');
          
          List<TextBlock> emptyBlocks = [];
          cardNumber = _extractCardNumber(tesseractText, emptyBlocks);
          expiryDate = expiryDate ?? _extractExpiryDate(tesseractText, emptyBlocks);
          cardholderName = cardholderName ?? _extractCardholderName(tesseractText, emptyBlocks);
          
          print('Tesseract results - Card: $cardNumber, Expiry: $expiryDate, Name: $cardholderName');
        } catch (e) {
          print('Tesseract failed: $e');
        }
      }

      if (cardNumber == null && preprocess) {
        print('\n--- ATTEMPT 4: Embossed Text Preprocessing + Tesseract ---');
        img.Image? embossedImage = await ImageUtils.preprocessForOCR(imagePath, forEmbossedText: true);
        if (embossedImage != null) {
          File processedFile = await ImageUtils.savePreprocessedImage(
            embossedImage,
            imagePath,
          );
          
          try {
            String tesseractText = await FlutterTesseractOcr.extractText(
              processedFile.path,
              language: 'eng',
              args: {
                "psm": "6",
                "preserve_interword_spaces": "1",
              },
            );
            
            print('Embossed preprocessing Tesseract text: $tesseractText');
            
            List<TextBlock> emptyBlocks = [];
            cardNumber = _extractCardNumber(tesseractText, emptyBlocks);
            expiryDate = expiryDate ?? _extractExpiryDate(tesseractText, emptyBlocks);
            cardholderName = cardholderName ?? _extractCardholderName(tesseractText, emptyBlocks);
            
            print('Embossed preprocessing results - Card: $cardNumber, Expiry: $expiryDate, Name: $cardholderName');
          } catch (e) {
            print('Embossed preprocessing Tesseract failed: $e');
          }
        }
      }
      
      if (cardNumber == null && preprocess) {
        print('\n--- ATTEMPT 5: Standard Preprocessing + Tesseract ---');
        img.Image? preprocessedImage = await ImageUtils.preprocessForOCR(imagePath, forEmbossedText: false);
        if (preprocessedImage != null) {
          File processedFile = await ImageUtils.savePreprocessedImage(
            preprocessedImage,
            imagePath,
          );
          
          try {
            String tesseractText = await FlutterTesseractOcr.extractText(
              processedFile.path,
              language: 'eng',
              args: {
                "psm": "6",
                "preserve_interword_spaces": "1",
              },
            );
            
            print('Standard preprocessing Tesseract text: $tesseractText');
            
            List<TextBlock> emptyBlocks = [];
            cardNumber = _extractCardNumber(tesseractText, emptyBlocks);
            expiryDate = expiryDate ?? _extractExpiryDate(tesseractText, emptyBlocks);
            cardholderName = cardholderName ?? _extractCardholderName(tesseractText, emptyBlocks);
            
            print('Standard preprocessing results - Card: $cardNumber, Expiry: $expiryDate, Name: $cardholderName');
          } catch (e) {
            print('Standard preprocessing Tesseract failed: $e');
          }
        }
      }

      String? cardType = cardNumber != null ? _detectCardType(cardNumber) : null;

      print('\n=== FINAL RESULTS ===');
      print('Card: $cardNumber');
      print('Expiry: $expiryDate');
      print('Name: $cardholderName');
      print('Type: $cardType');
      print('=== OCR PROCESSING END ===\n');

      return OCRResult(
        cardNumber: cardNumber,
        expiryDate: expiryDate,
        cardholderName: cardholderName,
        cardType: cardType,
      );
    } catch (e) {
      print('OCR Error: $e');
      throw Exception('Failed to process image: $e');
    }
  }

  String? _extractCardNumber(String text, List<TextBlock> textBlocks) {
    print('Extracting card number from text...');
    
    // Step 1: Look for patterns with spaces/dashes (most reliable for embossed cards)
    // Try both original and corrected text
    List<String> textsToTry = [text, ImageUtils.correctOCRCharacters(text)];
    
    for (String testText in textsToTry) {
      // Pattern for card numbers with spaces: "4150 2108 2914 633"
      RegExp spacedPattern = RegExp(r'([0-9iIlLoOsS]{4}[\s\-]+[0-9iIlLoOsS]{4}[\s\-]+[0-9iIlLoOsS]{4}[\s\-]+[0-9iIlLoOsS]{3,4})');
      Iterable<Match> matches = spacedPattern.allMatches(testText);
      
      for (Match match in matches) {
        String raw = match.group(1)!;
        print('Found spaced pattern: "$raw"');
        
        // Aggressive OCR correction for embossed numbers
        String corrected = raw
            .replaceAll('i', '1')
            .replaceAll('I', '1')
            .replaceAll('l', '1')
            .replaceAll('L', '1')
            .replaceAll('O', '0')
            .replaceAll('o', '0')
            .replaceAll('S', '5')
            .replaceAll('s', '5')
            .replaceAll('b', '6')
            .replaceAll('B', '8')
            .replaceAll(RegExp(r'[\s\-]'), '');
        
        print('Corrected to: $corrected (length: ${corrected.length})');
        
        if (corrected.length >= 13 && corrected.length <= 16) {
          if (_isValidLuhn(corrected)) {
            print('✓ Valid card from spaced pattern: $corrected');
            return corrected;
          }
          print('  Luhn check failed for: $corrected');
        }
      }
    }
    
    // Step 2: Check individual text blocks (each line of OCR)
    print('Checking ${textBlocks.length} text blocks...');
    List<String> blockCandidates = [];
    
    for (var block in textBlocks) {
      String blockText = block.text;
      // Look for lines that might be card numbers (contain digits and are long enough)
      if (blockText.replaceAll(RegExp(r'[^0-9]'), '').length >= 13) {
        String corrected = ImageUtils.correctOCRCharacters(blockText);
        String digitsOnly = corrected.replaceAll(RegExp(r'[^0-9]'), '');
        
        if (digitsOnly.length >= 13 && digitsOnly.length <= 19) {
          blockCandidates.add(digitsOnly);
          print('Block candidate: $digitsOnly (from: "${blockText.trim()}")');
        }
      }
    }

    // Check exact length matches first (most reliable)
    for (String candidate in blockCandidates) {
      if ((candidate.length == 16 || candidate.length == 15 || candidate.length == 13) && 
          _isValidLuhn(candidate)) {
        print('✓ Valid card from block: $candidate');
        return candidate;
      }
    }

    // Check substrings of longer sequences
    for (String candidate in blockCandidates) {
      if (candidate.length > 16) {
        for (int i = 0; i <= candidate.length - 13; i++) {
          for (int len in [16, 15, 13]) {
            if (i + len <= candidate.length) {
              String sub = candidate.substring(i, i + len);
              if (_isValidLuhn(sub)) {
                print('✓ Valid card extracted from block: $sub');
                return sub;
              }
            }
          }
        }
      }
    }

    print('✗ No valid card number found');
    return null;
  }

  bool _isValidLuhn(String cardNumber) {
    if (cardNumber.isEmpty) return false;
    
    int sum = 0;
    bool alternate = false;
    
    for (int i = cardNumber.length - 1; i >= 0; i--) {
      int digit = int.tryParse(cardNumber[i]) ?? 0;
      
      if (alternate) {
        digit *= 2;
        if (digit > 9) {
          digit -= 9;
        }
      }
      
      sum += digit;
      alternate = !alternate;
    }
    
    return sum % 10 == 0;
  }

  String? _extractExpiryDate(String text, List<TextBlock> textBlocks) {
    print('Extracting expiry date...');
    String correctedText = ImageUtils.correctOCRCharacters(text);
    
    List<RegExp> patterns = [
      RegExp(r'(?:VALID\s*THRU|EXPIRES?|GOOD\s*THRU|EXP\.?|EXPIRY)\s*:?\s*(0[1-9]|1[0-2])[/\-\s]?(\d{2,4})', caseSensitive: false),
      RegExp(r'\b(0[1-9]|1[0-2])[/\-](20)?(\d{2})\b'),
      RegExp(r'\b(0[1-9]|1[0-2])\s?[/\-]\s?(\d{2})\b'),
      RegExp(r'(?:^|\s)(0[1-9]|1[0-2])\s?/\s?(\d{2})(?:\s|$)'),
    ];

    for (var pattern in patterns) {
      Match? match = pattern.firstMatch(correctedText);
      if (match != null) {
        String month = match.group(1)!;
        String year = match.groupCount >= 3 && match.group(3) != null 
            ? match.group(3)! 
            : match.group(2)!;
        
        if (year.length == 4) {
          year = year.substring(2);
        }
        
        print('Testing expiry: $month/$year');
        if (_isValidExpiry(month, year)) {
          print('Valid expiry found: $month/$year');
          return '$month/$year';
        }
      }
    }

    RegExp loosePattern = RegExp(r'(0[1-9]|1[0-2])[\s/\-]?(\d{2})');
    Iterable<Match> matches = loosePattern.allMatches(correctedText);
    
    for (Match match in matches) {
      String month = match.group(1)!;
      String year = match.group(2)!;
      print('Testing loose match: $month/$year');
      if (_isValidExpiry(month, year)) {
        print('Valid expiry from loose match: $month/$year');
        return '$month/$year';
      }
    }

    print('No valid expiry date found');
    return null;
  }

  bool _isValidExpiry(String month, String year) {
    int monthNum = int.tryParse(month) ?? 0;
    if (monthNum < 1 || monthNum > 12) return false;

    int yearNum = int.tryParse(year) ?? 0;
    if (year.length == 4) {
      yearNum = yearNum % 100;
    }
    
    int currentYear = DateTime.now().year % 100;
    int currentMonth = DateTime.now().month;
    
    if (yearNum < currentYear) return false;
    if (yearNum > currentYear + 15) return false;
    if (yearNum == currentYear && monthNum < currentMonth) return false;
    
    return true;
  }

  String? _extractCardholderName(String text, List<TextBlock> textBlocks) {
    List<String> lines = text.split('\n');
    
    RegExp excludePattern = RegExp(
      r'(VISA|MASTERCARD|MASTER|AMEX|AMERICAN\s*EXPRESS|DISCOVER|RUPAY|DEBIT|CREDIT|CARD|BANK|VALID|THRU|EXPIRES?|EXPIRY|MEMBER|SINCE|PLATINUM|GOLD|SILVER|CLASSIC|SIGNATURE|INFINITE|WORLD|ELITE|REWARDS?|POINTS?|CASHBACK)',
      caseSensitive: false,
    );
    
    List<String> candidates = [];
    
    for (String line in lines) {
      String trimmedLine = line.trim().toUpperCase();
      
      if (trimmedLine.length >= 5 && 
          trimmedLine.length <= 30 &&
          !excludePattern.hasMatch(trimmedLine) &&
          !RegExp(r'\d').hasMatch(trimmedLine)) {
        
        List<String> words = trimmedLine.split(RegExp(r'\s+'));
        if (words.length >= 2 && words.length <= 4) {
          bool allWordsValid = words.every((word) => 
            word.length >= 2 && 
            RegExp(r'^[A-Z]+$').hasMatch(word)
          );
          
          if (allWordsValid) {
            candidates.add(trimmedLine);
          }
        }
      }
    }

    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => b.length.compareTo(a.length));
      return candidates.first;
    }

    return null;
  }

  String _detectCardType(String cardNumber) =>
      CardNetworkUtils.cardTypeFromNumber(cardNumber);

  void dispose() {
    _textRecognizer.close();
  }
}


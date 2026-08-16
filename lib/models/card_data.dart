// Initializing formals cannot preserve the public constructor labels while
// assigning these private encrypted fields.
// ignore_for_file: prefer_initializing_formals

import '../services/encryption_service.dart';

enum ReadMethod { nfc, camera, manual }

enum CardCategory { credit, debit }

class CardData {
  final String _encryptedCardNumber;
  final String _encryptedExpiryDate;
  final String? _encryptedCardholderName;
  final String? _encryptedCvv;
  final String? _encryptedAccountNumber;
  final String? _encryptedIfscCode;
  final String? _encryptedUpiId;
  final String lastFourDigits;
  final String cardType;
  final String? id;
  final DateTime? savedDate;
  final ReadMethod readMethod;
  final CardCategory cardCategory;
  final String? bankId;
  final String? cardNickname;
  final String? designId;
  final int? customGradientStartColor;
  final int? customGradientEndColor;
  final double customGradientAngle;
  final String? customBackgroundImagePath;
  final double backgroundImageBlur;
  final String? notes;
  final List<String> attachmentIds;
  final String? groupId;

  CardData({
    required String encryptedCardNumber,
    required String encryptedExpiryDate,
    String? encryptedCardholderName,
    String? encryptedCvv,
    String? encryptedAccountNumber,
    String? encryptedIfscCode,
    String? encryptedUpiId,
    required this.lastFourDigits,
    required this.cardType,
    this.id,
    this.savedDate,
    this.readMethod = ReadMethod.nfc,
    this.cardCategory = CardCategory.credit,
    this.bankId,
    this.cardNickname,
    this.designId,
    this.customGradientStartColor,
    this.customGradientEndColor,
    this.customGradientAngle = 135,
    this.customBackgroundImagePath,
    this.backgroundImageBlur = 0,
    this.notes,
    this.attachmentIds = const [],
    this.groupId,
  }) : _encryptedCardNumber = encryptedCardNumber,
       _encryptedExpiryDate = encryptedExpiryDate,
       _encryptedCardholderName = encryptedCardholderName,
       _encryptedCvv = encryptedCvv,
       _encryptedAccountNumber = encryptedAccountNumber,
       _encryptedIfscCode = encryptedIfscCode,
       _encryptedUpiId = encryptedUpiId;

  static Future<CardData> fromPlaintext({
    required String cardNumber,
    required String expiryDate,
    String? cardholderName,
    String? cvv,
    String? accountNumber,
    String? ifscCode,
    String? upiId,
    required String cardType,
    String? id,
    DateTime? savedDate,
    ReadMethod readMethod = ReadMethod.nfc,
    CardCategory cardCategory = CardCategory.credit,
    String? bankId,
    String? cardNickname,
    String? designId,
    int? customGradientStartColor,
    int? customGradientEndColor,
    double customGradientAngle = 135,
    String? customBackgroundImagePath,
    double backgroundImageBlur = 0,
    String? notes,
    List<String>? attachmentIds,
    String? groupId,
  }) async {
    final encryptionService = EncryptionService();

    final encryptedCardNumber = await encryptionService.encrypt(cardNumber);
    final encryptedExpiryDate = await encryptionService.encrypt(expiryDate);
    final encryptedCardholderName = cardholderName != null
        ? await encryptionService.encrypt(cardholderName)
        : null;
    final encryptedCvv = cvv != null
        ? await encryptionService.encrypt(cvv)
        : null;
    final encryptedAccountNumber = accountNumber != null
        ? await encryptionService.encrypt(accountNumber)
        : null;
    final encryptedIfscCode = ifscCode != null
        ? await encryptionService.encrypt(ifscCode)
        : null;
    final encryptedUpiId = upiId != null
        ? await encryptionService.encrypt(upiId)
        : null;

    final lastFour = cardNumber.length >= 4
        ? cardNumber.substring(cardNumber.length - 4)
        : cardNumber;

    return CardData(
      encryptedCardNumber: encryptedCardNumber,
      encryptedExpiryDate: encryptedExpiryDate,
      encryptedCardholderName: encryptedCardholderName,
      encryptedCvv: encryptedCvv,
      encryptedAccountNumber: encryptedAccountNumber,
      encryptedIfscCode: encryptedIfscCode,
      encryptedUpiId: encryptedUpiId,
      lastFourDigits: lastFour,
      cardType: cardType,
      id: id,
      savedDate: savedDate,
      readMethod: readMethod,
      cardCategory: cardCategory,
      bankId: bankId,
      cardNickname: cardNickname,
      designId: designId,
      customGradientStartColor: customGradientStartColor,
      customGradientEndColor: customGradientEndColor,
      customGradientAngle: customGradientAngle,
      customBackgroundImagePath: customBackgroundImagePath,
      backgroundImageBlur: backgroundImageBlur,
      notes: notes,
      attachmentIds: attachmentIds ?? const [],
      groupId: groupId,
    );
  }

  Future<String> getDecryptedCardNumber() async {
    final encryptionService = EncryptionService();
    return await encryptionService.decrypt(_encryptedCardNumber);
  }

  Future<String> getDecryptedExpiryDate() async {
    final encryptionService = EncryptionService();
    return await encryptionService.decrypt(_encryptedExpiryDate);
  }

  Future<String?> getDecryptedCardholderName() async {
    if (_encryptedCardholderName == null) return null;
    final encryptionService = EncryptionService();
    return await encryptionService.decrypt(_encryptedCardholderName);
  }

  Future<String?> getDecryptedCvv() async {
    if (_encryptedCvv == null) return null;
    final encryptionService = EncryptionService();
    return await encryptionService.decrypt(_encryptedCvv);
  }

  Future<String?> getDecryptedAccountNumber() async {
    if (_encryptedAccountNumber == null) return null;
    final encryptionService = EncryptionService();
    return await encryptionService.decrypt(_encryptedAccountNumber);
  }

  Future<String?> getDecryptedIfscCode() async {
    if (_encryptedIfscCode == null) return null;
    final encryptionService = EncryptionService();
    return await encryptionService.decrypt(_encryptedIfscCode);
  }

  Future<String?> getDecryptedUpiId() async {
    if (_encryptedUpiId == null) return null;
    final encryptionService = EncryptionService();
    return await encryptionService.decrypt(_encryptedUpiId);
  }

  String get maskedCardNumber {
    if (lastFourDigits.length == 4) {
      return '**** **** **** $lastFourDigits';
    }
    return '**** $lastFourDigits';
  }

  String get maskedCvv => '***';

  String get categoryName =>
      cardCategory == CardCategory.credit ? 'Credit' : 'Debit';

  Future<String> getFormattedCardNumber() async {
    final cardNumber = await getDecryptedCardNumber();
    if (cardNumber.length >= 16) {
      return '${cardNumber.substring(0, 4)} ${cardNumber.substring(4, 8)} ${cardNumber.substring(8, 12)} ${cardNumber.substring(12)}';
    }
    return cardNumber;
  }

  CardData copyWith({
    String? encryptedCardNumber,
    String? encryptedExpiryDate,
    String? encryptedCardholderName,
    String? encryptedCvv,
    String? encryptedAccountNumber,
    String? encryptedIfscCode,
    String? encryptedUpiId,
    String? lastFourDigits,
    String? cardType,
    String? id,
    DateTime? savedDate,
    ReadMethod? readMethod,
    CardCategory? cardCategory,
    String? bankId,
    String? cardNickname,
    String? designId,
    int? customGradientStartColor,
    int? customGradientEndColor,
    double? customGradientAngle,
    String? customBackgroundImagePath,
    double? backgroundImageBlur,
    String? notes,
    List<String>? attachmentIds,
    String? groupId,
    bool clearGroup = false,
    bool clearDesign = false,
    bool clearCustomGradient = false,
    bool clearCustomBackgroundImage = false,
  }) {
    return CardData(
      encryptedCardNumber: encryptedCardNumber ?? _encryptedCardNumber,
      encryptedExpiryDate: encryptedExpiryDate ?? _encryptedExpiryDate,
      encryptedCardholderName:
          encryptedCardholderName ?? _encryptedCardholderName,
      encryptedCvv: encryptedCvv ?? _encryptedCvv,
      encryptedAccountNumber: encryptedAccountNumber ?? _encryptedAccountNumber,
      encryptedIfscCode: encryptedIfscCode ?? _encryptedIfscCode,
      encryptedUpiId: encryptedUpiId ?? _encryptedUpiId,
      lastFourDigits: lastFourDigits ?? this.lastFourDigits,
      cardType: cardType ?? this.cardType,
      id: id ?? this.id,
      savedDate: savedDate ?? this.savedDate,
      readMethod: readMethod ?? this.readMethod,
      cardCategory: cardCategory ?? this.cardCategory,
      bankId: bankId ?? this.bankId,
      cardNickname: cardNickname ?? this.cardNickname,
      designId: clearDesign ? null : (designId ?? this.designId),
      customGradientStartColor: clearCustomGradient
          ? null
          : (customGradientStartColor ?? this.customGradientStartColor),
      customGradientEndColor: clearCustomGradient
          ? null
          : (customGradientEndColor ?? this.customGradientEndColor),
      customGradientAngle: customGradientAngle ?? this.customGradientAngle,
      customBackgroundImagePath: clearCustomBackgroundImage
          ? null
          : (customBackgroundImagePath ?? this.customBackgroundImagePath),
      backgroundImageBlur: backgroundImageBlur ?? this.backgroundImageBlur,
      notes: notes ?? this.notes,
      attachmentIds: attachmentIds ?? this.attachmentIds,
      groupId: clearGroup ? null : (groupId ?? this.groupId),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'encryptedCardNumber': _encryptedCardNumber,
      'encryptedExpiryDate': _encryptedExpiryDate,
      'encryptedCardholderName': _encryptedCardholderName,
      'encryptedCvv': _encryptedCvv,
      'encryptedAccountNumber': _encryptedAccountNumber,
      'encryptedIfscCode': _encryptedIfscCode,
      'encryptedUpiId': _encryptedUpiId,
      'lastFourDigits': lastFourDigits,
      'cardType': cardType,
      'id': id,
      'savedDate': savedDate?.toIso8601String(),
      'readMethod': readMethod.name,
      'cardCategory': cardCategory.name,
      'bankId': bankId,
      'cardNickname': cardNickname,
      'designId': designId,
      'customGradientStartColor': customGradientStartColor,
      'customGradientEndColor': customGradientEndColor,
      'customGradientAngle': customGradientAngle,
      'customBackgroundImagePath': customBackgroundImagePath,
      'backgroundImageBlur': backgroundImageBlur,
      'notes': notes,
      'attachmentIds': attachmentIds,
      'groupId': groupId,
    };
  }

  factory CardData.fromJson(Map<String, dynamic> json) {
    return CardData(
      encryptedCardNumber: json['encryptedCardNumber'] as String,
      encryptedExpiryDate: json['encryptedExpiryDate'] as String,
      encryptedCardholderName: json['encryptedCardholderName'] as String?,
      encryptedCvv: json['encryptedCvv'] as String?,
      encryptedAccountNumber: json['encryptedAccountNumber'] as String?,
      encryptedIfscCode: json['encryptedIfscCode'] as String?,
      encryptedUpiId: json['encryptedUpiId'] as String?,
      lastFourDigits: json['lastFourDigits'] as String,
      cardType: json['cardType'] as String,
      id: json['id'] as String?,
      savedDate: json['savedDate'] != null
          ? DateTime.parse(json['savedDate'] as String)
          : null,
      readMethod: json['readMethod'] != null
          ? ReadMethod.values.firstWhere(
              (e) => e.name == json['readMethod'],
              orElse: () => ReadMethod.nfc,
            )
          : ReadMethod.nfc,
      cardCategory: json['cardCategory'] != null
          ? CardCategory.values.firstWhere(
              (e) => e.name == json['cardCategory'],
              orElse: () => CardCategory.credit,
            )
          : CardCategory.credit,
      bankId: json['bankId'] as String?,
      cardNickname: json['cardNickname'] as String?,
      designId: json['designId'] as String?,
      customGradientStartColor: (json['customGradientStartColor'] as num?)
          ?.toInt(),
      customGradientEndColor: (json['customGradientEndColor'] as num?)?.toInt(),
      customGradientAngle:
          (json['customGradientAngle'] as num?)?.toDouble() ?? 135,
      customBackgroundImagePath: json['customBackgroundImagePath'] as String?,
      backgroundImageBlur:
          (json['backgroundImageBlur'] as num?)?.toDouble() ?? 0,
      notes: json['notes'] as String?,
      attachmentIds:
          (json['attachmentIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      groupId: json['groupId'] as String?,
    );
  }

  static bool isValidCardNumber(String cardNumber) {
    String cleaned = cardNumber.replaceAll(RegExp(r'[\s\-]'), '');

    if (cleaned.length < 13 || cleaned.length > 19) {
      return false;
    }

    if (!RegExp(r'^\d+$').hasMatch(cleaned)) {
      return false;
    }

    return _luhnCheck(cleaned);
  }

  static bool _luhnCheck(String cardNumber) {
    int sum = 0;
    bool alternate = false;

    for (int i = cardNumber.length - 1; i >= 0; i--) {
      int digit = int.parse(cardNumber[i]);

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

  static bool isValidExpiryDate(String expiryDate) {
    RegExp expiryPattern = RegExp(r'^(0[1-9]|1[0-2])/(\d{2})$');

    if (!expiryPattern.hasMatch(expiryDate)) {
      return false;
    }

    List<String> parts = expiryDate.split('/');
    int month = int.parse(parts[0]);
    int year = int.parse(parts[1]) + 2000;

    DateTime now = DateTime.now();
    DateTime cardExpiry = DateTime(year, month + 1, 0);

    return cardExpiry.isAfter(now);
  }

  static bool isValidCvv(String cvv) {
    return RegExp(r'^\d{3,4}$').hasMatch(cvv);
  }

  @override
  String toString() {
    return 'CardData(cardNumber: $maskedCardNumber, cardType: $cardType, lastFour: $lastFourDigits, readMethod: $readMethod, category: $categoryName)';
  }
}

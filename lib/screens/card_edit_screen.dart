import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/card_data.dart';
import '../models/card_group.dart';
import '../data/banks.dart';
import '../data/card_designs.dart';
import '../services/card_group_storage.dart';
import '../services/ocr_service.dart';
import '../services/secure_card_storage.dart';
import '../services/encryption_service.dart';
import '../services/card_attachment_storage.dart';
import '../widgets/bank_logo.dart';
import '../widgets/card_attachments.dart';
import '../widgets/card_network_logo.dart';
import '../widgets/group_picker_sheet.dart';
import '../widgets/wallet_card.dart';
import '../utils/card_formatter.dart';
import '../utils/card_network_utils.dart';
import '../providers/theme_provider.dart';
import '../theme/app_typography.dart';

class CardEditScreen extends StatefulWidget {
  final CardData? card;
  final OCRResult? ocrResult;

  const CardEditScreen({
    super.key,
    this.card,
    this.ocrResult,
  }) : assert(card != null || ocrResult != null);

  @override
  State<CardEditScreen> createState() => _CardEditScreenState();
}

class _CardEditScreenState extends State<CardEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cardStorage = SecureCardStorage();
  final _encryptionService = EncryptionService();
  final _attachmentStorage = CardAttachmentStorage();
  List<String> _existingAttachmentIds = [];
  List<File> _pendingAttachmentFiles = [];
  List<String> _removedAttachmentIds = [];

  late TextEditingController _cardNumberController;
  late TextEditingController _expiryController;
  late TextEditingController _cvvController;
  late TextEditingController _cardholderController;
  late TextEditingController _nicknameController;
  late TextEditingController _accountNumberController;
  late TextEditingController _ifscCodeController;
  late TextEditingController _upiIdController;
  late TextEditingController _notesController;

  CardCategory _cardCategory = CardCategory.credit;
  BankInfo? _selectedBank;
  CardGroup? _selectedGroup;
  CardDesign? _selectedDesign;
  CardDesignStyle _selectedStyle = CardDesignStyle.gradient;
  String? _detectedCardType;
  bool _isLoading = false;
  bool _isInitialized = false;
  Set<String> _existingCardholderNames = {};
  CardNetwork _detectedNetwork = CardNetwork.unknown;

  @override
  void initState() {
    super.initState();
    _cardNumberController = TextEditingController();
    _expiryController = TextEditingController();
    _cvvController = TextEditingController();
    _cardholderController = TextEditingController();
    _nicknameController = TextEditingController();
    _accountNumberController = TextEditingController();
    _ifscCodeController = TextEditingController();
    _upiIdController = TextEditingController();
    _notesController = TextEditingController();
    _loadExistingCardholders();
    _initializeData();
  }
  
  Future<void> _loadExistingCardholders() async {
    try {
      final cards = await _cardStorage.loadCards();
      final names = await Future.wait(
        cards.map((c) => c.getDecryptedCardholderName()).toList(),
      );
      setState(() {
        _existingCardholderNames = names.whereType<String>().toSet();
      });
    } catch (e) {
      // Ignore errors loading existing names
    }
  }

  Future<void> _initializeData() async {
    if (widget.card != null) {
      final card = widget.card!;
      final cardNumber = await card.getDecryptedCardNumber();
      final expiry = await card.getDecryptedExpiryDate();
      final cardholder = await card.getDecryptedCardholderName();
      final cvv = await card.getDecryptedCvv();
      final accountNumber = await card.getDecryptedAccountNumber();
      final ifscCode = await card.getDecryptedIfscCode();
      final upiId = await card.getDecryptedUpiId();
      final group = card.groupId != null
          ? await CardGroupStorage().loadGroup(card.groupId!)
          : null;

      if (mounted) {
      setState(() {
        _detectedNetwork = CardNetworkUtils.detectNetwork(cardNumber);
        _cardNumberController.text = _formatCardNumber(cardNumber);
        _expiryController.text = expiry;
        _cardholderController.text = cardholder ?? '';
        _cvvController.text = cvv ?? '';
        _nicknameController.text = card.cardNickname ?? '';
        _accountNumberController.text = accountNumber ?? '';
        _ifscCodeController.text = ifscCode ?? '';
        _upiIdController.text = upiId ?? '';
        _notesController.text = card.notes ?? '';
        _existingAttachmentIds = List<String>.from(card.attachmentIds);
        _cardCategory = card.cardCategory;
        _selectedBank = card.bankId != null ? Banks.getById(card.bankId!) : null;
        _selectedGroup = group;
        _selectedDesign = card.designId != null ? CardDesigns.getById(card.designId!) : null;
        if (_selectedDesign != null) {
          _selectedStyle = _selectedDesign!.style;
        }
        _detectedCardType = card.cardType;
        _isInitialized = true;
      });
      }
    } else if (widget.ocrResult != null) {
      setState(() {
        final cardNum = widget.ocrResult!.cardNumber ?? '';
        _detectedNetwork = CardNetworkUtils.detectNetwork(cardNum);
        _cardNumberController.text = _formatCardNumber(cardNum);
        _expiryController.text = widget.ocrResult!.expiryDate ?? '';
        _cardholderController.text = widget.ocrResult!.cardholderName ?? '';
        _detectedCardType = widget.ocrResult!.cardType;
        _isInitialized = true;
      });
    }

    _cardNumberController.addListener(_updateCardType);
  }

  @override
  void dispose() {
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _cardholderController.dispose();
    _nicknameController.dispose();
    _accountNumberController.dispose();
    _ifscCodeController.dispose();
    _upiIdController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _updateCardType() {
    String cardNumber = _cardNumberController.text.replaceAll(RegExp(r'[\s\-]'), '');
    if (cardNumber.isNotEmpty) {
      setState(() {
        _detectedCardType = _detectCardType(cardNumber);
      });
    }
  }

  String _detectCardType(String cardNumber) =>
      CardNetworkUtils.cardTypeFromNumber(cardNumber);

  String _formatCardNumber(String text) {
    text = text.replaceAll(RegExp(r'[\s\-]'), '');
    return CardNetworkUtils.formatCardNumber(text, _detectedNetwork);
  }

  String _formatExpiry(String text) {
    text = text.replaceAll('/', '');
    if (text.length >= 2) {
      return '${text.substring(0, 2)}/${text.substring(2)}';
    }
    return text;
  }

  Future<void> _saveCard() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final cardNumber = _cardNumberController.text.replaceAll(' ', '');
      final expiry = _expiryController.text;
      final cardholder = _cardholderController.text.isEmpty ? null : _cardholderController.text;
      final cvv = _cvvController.text.isEmpty ? null : _cvvController.text;
      final nickname = _nicknameController.text.isEmpty ? null : _nicknameController.text;
      final accountNumber = _accountNumberController.text.isEmpty ? null : _accountNumberController.text;
      final ifscCode = _ifscCodeController.text.isEmpty ? null : _ifscCodeController.text;
      final upiId = _upiIdController.text.isEmpty ? null : _upiIdController.text;
      final notes = _notesController.text.isEmpty ? null : _notesController.text;

      if (widget.card != null && widget.card!.id != null) {
        final encryptedCardNumber = await _encryptionService.encrypt(cardNumber);
        final encryptedExpiry = await _encryptionService.encrypt(expiry);
        final encryptedCardholder = cardholder != null
            ? await _encryptionService.encrypt(cardholder)
            : null;
        final encryptedCvv = cvv != null
            ? await _encryptionService.encrypt(cvv)
            : null;
        final encryptedAccountNumber = accountNumber != null
            ? await _encryptionService.encrypt(accountNumber)
            : null;
        final encryptedIfscCode = ifscCode != null
            ? await _encryptionService.encrypt(ifscCode)
            : null;
        final encryptedUpiId = upiId != null
            ? await _encryptionService.encrypt(upiId)
            : null;

        final cardId = widget.card!.id!;
        await _attachmentStorage.deleteAttachments(cardId, _removedAttachmentIds);
        final newIds = await _attachmentStorage.saveAttachments(cardId, _pendingAttachmentFiles);

        final updatedCard = widget.card!.copyWith(
          encryptedCardNumber: encryptedCardNumber,
          encryptedExpiryDate: encryptedExpiry,
          encryptedCardholderName: encryptedCardholder,
          encryptedCvv: encryptedCvv,
          encryptedAccountNumber: encryptedAccountNumber,
          encryptedIfscCode: encryptedIfscCode,
          encryptedUpiId: encryptedUpiId,
          lastFourDigits: cardNumber.substring(cardNumber.length - 4),
          cardType: _detectedCardType ?? 'Unknown',
          cardCategory: _cardCategory,
          bankId: _selectedBank?.id,
          cardNickname: nickname,
          designId: _selectedDesign?.id,
          notes: notes,
          attachmentIds: [..._existingAttachmentIds, ...newIds],
          groupId: _selectedGroup?.id,
          clearGroup: _selectedGroup == null,
        );

        await _cardStorage.updateCard(updatedCard);

        _removedAttachmentIds = [];
        _pendingAttachmentFiles = [];

        if (mounted) {
          Navigator.pop(context, updatedCard);
        }
      } else {
        final card = await CardData.fromPlaintext(
          cardNumber: cardNumber,
          expiryDate: expiry,
          cardholderName: cardholder,
          cvv: cvv,
          accountNumber: accountNumber,
          ifscCode: ifscCode,
          upiId: upiId,
          cardType: _detectedCardType ?? 'Unknown',
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          savedDate: DateTime.now(),
          readMethod: ReadMethod.camera,
          cardCategory: _cardCategory,
          bankId: _selectedBank?.id,
          cardNickname: nickname,
          designId: _selectedDesign?.id,
          notes: notes,
          attachmentIds: const [],
          groupId: _selectedGroup?.id,
        );

        if (mounted) {
          Navigator.pop(context, card);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save card: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: themeProvider.getBackgroundColor(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: themeProvider.getBackgroundColor(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: themeProvider.getPrimaryTextColor()),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.card != null ? 'Edit Card' : 'Review Card',
          style: AppTypography.appBarTitle(
            color: themeProvider.getPrimaryTextColor(),
          ),
        ),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.ocrResult != null) _buildInfoBanner(),
              if (widget.ocrResult != null) const SizedBox(height: 16),
              _buildPreviewCard(),
              const SizedBox(height: 24),
              _buildSectionTitle('Card Information'),
              const SizedBox(height: 12),
              _buildCardNumberField(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildExpiryField()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildCvvField()),
                ],
              ),
              const SizedBox(height: 16),
              _buildCardholderField(),
              const SizedBox(height: 24),
              _buildSectionTitle('Card Type'),
              const SizedBox(height: 12),
              _buildCardCategorySelector(),
              const SizedBox(height: 24),
              _buildSectionTitle('Bank'),
              const SizedBox(height: 12),
              _buildBankSelector(),
              const SizedBox(height: 24),
              _buildSectionTitle('Group'),
              const SizedBox(height: 12),
              GroupSelectorField(
                selectedGroup: _selectedGroup,
                onChanged: (group) => setState(() => _selectedGroup = group),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle('Card Nickname'),
              const SizedBox(height: 12),
              _buildNicknameField(),
              const SizedBox(height: 24),
              _buildSectionTitle('Card Design'),
              const SizedBox(height: 12),
              _buildDesignStyleSelector(),
              const SizedBox(height: 12),
              _buildDesignSelector(),
              const SizedBox(height: 24),
              _buildSectionTitle('Additional Information'),
              const SizedBox(height: 12),
              _buildAdditionalInfoFields(),
              const SizedBox(height: 32),
              _buildSaveButton(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue.shade700, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Review and correct the extracted card details',
              style: AppTypography.listItem(
                color: Colors.blue.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard() {
    final themeProvider = context.watch<ThemeProvider>();
    final primaryColor = _selectedDesign?.primaryColor ??
        _selectedBank?.primaryColor ??
        themeProvider.getPrimaryColor();
    final secondaryColor = _selectedDesign?.secondaryColor ??
        _selectedBank?.secondaryColor ??
        themeProvider.getPrimaryContainerColor();

    return AspectRatio(
      aspectRatio: 1.586,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primaryColor, secondaryColor],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            if (_selectedDesign?.hasCircles ?? false) _buildCircles(),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _cardCategory == CardCategory.credit ? 'Credit' : 'Debit',
                                style: AppTypography.cardName(color: Colors.white),
                              ),
                              Text(
                                'Card',
                                style: AppTypography.cardNameLight(color: Colors.white70),
                              ),
                            ],
                          ),
                          if (_nicknameController.text.isNotEmpty)
                            Text(
                              _nicknameController.text,
                              style: AppTypography.caption(
                                fontSize: 11,
                                color: Colors.white60,
                              ),
                            ),
                        ],
                      ),
                      Icon(Icons.contactless, color: Colors.white.withOpacity(0.7), size: 24),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    _cardNumberController.text.isEmpty
                        ? '**** **** **** ****'
                        : _cardNumberController.text,
                    style: AppTypography.mono(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        _cardholderController.text.isEmpty
                            ? 'YOUR NAME'
                            : _cardholderController.text.toUpperCase(),
                        style: AppTypography.caption(
                          color: Colors.white70,
                        ).copyWith(fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      Text(
                        _expiryController.text.isEmpty ? 'MM/YY' : _expiryController.text,
                        style: AppTypography.mono(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildCircles() {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final circleSize = constraints.maxHeight * 0.5;
          return Stack(
            children: [
              Positioned(
                left: 16,
                top: (constraints.maxHeight - circleSize) / 2,
                child: Container(
                  width: circleSize,
                  height: circleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE85D3F).withOpacity(0.85),
                  ),
                ),
              ),
              Positioned(
                left: 16 + circleSize * 0.5,
                top: (constraints.maxHeight - circleSize) / 2,
                child: Container(
                  width: circleSize,
                  height: circleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE85D3F).withOpacity(0.6),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    final themeProvider = context.watch<ThemeProvider>();
    return Text(
      title,
      style: AppTypography.title(
        color: themeProvider.getPrimaryTextColor(),
      ),
    );
  }

  Widget _buildCardNumberField() {
    final themeProvider = context.watch<ThemeProvider>();
    
    return TextFormField(
      controller: _cardNumberController,
      keyboardType: TextInputType.number,
      inputFormatters: [
        CardNumberFormatter(network: _detectedNetwork),
      ],
      decoration: _inputDecoration('Card Number', Icons.credit_card).copyWith(
        suffixIcon: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CardNetworkLogo(
            cardNumber: _cardNumberController.text,
            height: 18,
            isInputField: true,
          ),
        ),
      ),
      style: AppTypography.mono(
        fontSize: 16,
        letterSpacing: 1,
        color: themeProvider.getPrimaryTextColor(),
      ),
      onChanged: (value) {
        final cleaned = value.replaceAll(' ', '');
        final newNetwork = CardNetworkUtils.detectNetwork(cleaned);
        if (newNetwork != _detectedNetwork) {
          setState(() {
            _detectedNetwork = newNetwork;
          });
        }
      },
      validator: (value) {
        if (value == null || value.isEmpty) return 'Required';
        final cleaned = value.replaceAll(' ', '');
        if (cleaned.length < 13) return 'Invalid card number';
        if (!CardData.isValidCardNumber(cleaned)) return 'Invalid card number';
        return null;
      },
    );
  }

  Widget _buildExpiryField() {
    final themeProvider = context.watch<ThemeProvider>();
    
    return TextFormField(
      controller: _expiryController,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
        ExpiryDateFormatter(),
      ],
      decoration: _inputDecoration('MM/YY', Icons.calendar_today),
      style: AppTypography.mono(
        fontSize: 16,
        color: themeProvider.getPrimaryTextColor(),
      ),
      onChanged: (value) {
        setState(() {});
      },
      validator: (value) {
        if (value == null || value.isEmpty) return 'Required';
        if (!CardData.isValidExpiryDate(value)) return 'Invalid';
        return null;
      },
    );
  }

  Widget _buildCvvField() {
    final themeProvider = context.watch<ThemeProvider>();
    final cvvLength = CardNetworkUtils.getCvvLength(_detectedNetwork);
    final cvvLabel = CardNetworkUtils.getCvvLabel(_detectedNetwork);
    
    return TextFormField(
      controller: _cvvController,
      keyboardType: TextInputType.number,
      obscureText: true,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(cvvLength),
        CvvFormatter(network: _detectedNetwork),
      ],
      decoration: _inputDecoration(cvvLabel, Icons.lock_outline),
      style: AppTypography.mono(
        fontSize: 16,
        color: themeProvider.getPrimaryTextColor(),
      ),
      validator: (value) {
        if (value != null && value.isNotEmpty) {
          if (value.length != cvvLength) {
            return 'Must be $cvvLength digits';
          }
          if (!CardData.isValidCvv(value)) {
            return 'Invalid';
          }
        }
        return null;
      },
    );
  }

  Widget _buildCardholderField() {
    final themeProvider = context.watch<ThemeProvider>();
    
    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<String>.empty();
        }
        return _existingCardholderNames.where((name) =>
          name.toLowerCase().contains(textEditingValue.text.toLowerCase())
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Material(
              elevation: 4,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200, maxWidth: 400),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    return InkWell(
                      onTap: () => onSelected(option),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Text(
                          option,
                          style: AppTypography.listItem(
                            color: themeProvider.getPrimaryTextColor(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
      onSelected: (String selection) {
        setState(() {
          _cardholderController.text = selection;
        });
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        if (controller.text != _cardholderController.text) {
          controller.text = _cardholderController.text;
        }
        
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          decoration: _inputDecoration('Cardholder Name', Icons.person_outline),
          style: AppTypography.bodyLarge(
            color: themeProvider.getPrimaryTextColor(),
          ),
          onChanged: (value) {
            _cardholderController.text = value;
            setState(() {});
          },
        );
      },
    );
  }

  Widget _buildNicknameField() {
    return TextFormField(
      controller: _nicknameController,
      decoration: _inputDecoration('e.g., ICICI Coral, Axis Priority', null),
      style: AppTypography.bodyLarge(),
      onChanged: (_) => setState(() {}),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData? icon) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDarkMode;
    
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTypography.style(
        color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
      ),
      prefixIcon: icon != null ? Icon(
        icon, 
        color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
      ) : null,
      filled: true,
      fillColor: Colors.transparent,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: isDark ? Colors.white.withOpacity(0.2) : const Color(0xFFD1D5DB),
          width: 1.5,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: isDark ? Colors.white.withOpacity(0.2) : const Color(0xFFD1D5DB),
          width: 1.5,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: isDark ? themeProvider.getPrimaryColor() : const Color(0xFF374151),
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  Widget _buildCardCategorySelector() {
    return Row(
      children: [
        Expanded(child: _buildCategoryChip(CardCategory.credit, 'Credit')),
        const SizedBox(width: 12),
        Expanded(child: _buildCategoryChip(CardCategory.debit, 'Debit')),
      ],
    );
  }

  Widget _buildCategoryChip(CardCategory category, String label) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDarkMode;
    final isSelected = _cardCategory == category;
    return GestureDetector(
      onTap: () => setState(() => _cardCategory = category),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF374151) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF374151) : (isDark ? Colors.white.withOpacity(0.2) : const Color(0xFFD1D5DB)),
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTypography.label(
              color: isSelected ? Colors.white : themeProvider.getPrimaryTextColor(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBankSelector() {
    final themeProvider = context.watch<ThemeProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Popular Banks',
          style: AppTypography.caption(color: themeProvider.getSecondaryTextColor()),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: Banks.popular.map((bank) => _buildBankChip(bank)).toList(),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => _showBankSelectionModal(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: context.watch<ThemeProvider>().isDarkMode 
                    ? Colors.white.withOpacity(0.2) 
                    : const Color(0xFFD1D5DB),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                if (_selectedBank != null) ...[
                  BankLogo(bank: _selectedBank, size: 24, useSmall: true),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    _selectedBank?.name ?? 'Select Bank',
                    style: AppTypography.bodyLarge(
                      color: _selectedBank != null
                          ? context.watch<ThemeProvider>().getPrimaryTextColor()
                          : (context.watch<ThemeProvider>().isDarkMode 
                              ? Colors.grey.shade600 
                              : Colors.grey.shade400),
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  color: context.watch<ThemeProvider>().getSecondaryTextColor(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBankChip(BankInfo bank) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDarkMode;
    final isSelected = _selectedBank?.id == bank.id;
    return GestureDetector(
      onTap: () => setState(() => _selectedBank = bank),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? bank.primaryColor.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? bank.primaryColor : (isDark ? Colors.white.withOpacity(0.2) : const Color(0xFFD1D5DB)),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BankLogo(bank: bank, size: 18, useSmall: true),
            const SizedBox(width: 6),
            Text(
              bank.shortName,
              style: AppTypography.label(
                fontSize: 11,
                color: isSelected ? bank.primaryColor : themeProvider.getPrimaryTextColor(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesignStyleSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: CardDesignStyle.values.map((style) {
          final isSelected = _selectedStyle == style;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedStyle = style;
                  _selectedDesign = null;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF374151) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF374151) : const Color(0xFFD1D5DB),
                  ),
                ),
                child: Text(
                  CardDesigns.getStyleName(style),
                  style: AppTypography.label(
                    color: isSelected ? Colors.white : Colors.black87,
                  ).copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDesignSelector() {
    final designs = CardDesigns.getByStyle(_selectedStyle);
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: designs.length,
        itemBuilder: (context, index) {
          final design = designs[index];
          final isSelected = _selectedDesign?.id == design.id;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => setState(() => _selectedDesign = design),
              child: Container(
                width: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [design.primaryColor, design.secondaryColor],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 3)
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: design.primaryColor.withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    design.name.split(' ').first,
                    style: AppTypography.label(
                      fontSize: 11,
                      color: _isLightColor(design.primaryColor)
                          ? Colors.black87
                          : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  bool _isLightColor(Color color) {
    return color.computeLuminance() > 0.5;
  }

  Widget _buildAdditionalInfoFields() {
    return Column(
      children: [
        TextFormField(
          controller: _accountNumberController,
          decoration: _inputDecoration('Bank Account Number', Icons.account_balance_wallet),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(20),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _ifscCodeController,
          decoration: _inputDecoration('IFSC Code', Icons.code),
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            LengthLimitingTextInputFormatter(11),
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _upiIdController,
          decoration: _inputDecoration('UPI ID', Icons.qr_code),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _notesController,
          decoration: _inputDecoration('Notes', Icons.note),
          maxLines: 3,
          maxLength: 500,
        ),
        const SizedBox(height: 16),
        CardAttachmentsEditor(
          cardId: widget.card?.id,
          existingIds: _existingAttachmentIds,
          pendingFiles: _pendingAttachmentFiles,
          onExistingChanged: (ids) {
            final removed = _existingAttachmentIds.where((id) => !ids.contains(id));
            setState(() {
              _removedAttachmentIds.addAll(removed);
              _existingAttachmentIds = ids;
            });
          },
          onPendingChanged: (files) => setState(() => _pendingAttachmentFiles = files),
        ),
      ],
    );
  }

  void _showBankSelectionModal() {
    final TextEditingController searchController = TextEditingController();
    List<BankInfo> filteredBanks = Banks.allSorted;
    const double bankTileExtent = 60;
    final selectedIndex = filteredBanks.indexWhere((b) => b.id == _selectedBank?.id);
    final scrollController = ScrollController(
      initialScrollOffset: selectedIndex > 0 ? selectedIndex * bankTileExtent : 0,
    );
    final themeProvider = context.read<ThemeProvider>();
    final sheetColor = themeProvider.getCardColor();
    final primaryText = themeProvider.getPrimaryTextColor();
    final secondaryText = themeProvider.getSecondaryTextColor();
    final outline = themeProvider.getOutlineColor();
    final selectedColor = themeProvider.getPrimaryContainerColor();
    final searchFill = themeProvider.colorScheme.surfaceContainerHighest;
    final accent = themeProvider.getPrimaryColor();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.75,
                decoration: BoxDecoration(
                  color: sheetColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Select Bank',
                              style: AppTypography.sectionTitle(color: primaryText),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: primaryText),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: outline),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemExtent: bankTileExtent,
                        itemCount: filteredBanks.length,
                        itemBuilder: (context, index) {
                          final bank = filteredBanks[index];
                          final isSelected = _selectedBank?.id == bank.id;
                          return ListTile(
                            leading: BankLogo(bank: bank, size: 32, useSmall: true),
                            title: Text(
                              bank.name,
                              style: AppTypography.body(color: primaryText),
                            ),
                            trailing: isSelected
                                ? Icon(Icons.check, color: accent)
                                : null,
                            selected: isSelected,
                            selectedTileColor: selectedColor,
                            onTap: () {
                              setState(() => _selectedBank = bank);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: sheetColor,
                        border: Border(
                          top: BorderSide(color: outline, width: 1),
                        ),
                      ),
                      child: TextField(
                        controller: searchController,
                        autofocus: false,
                        style: AppTypography.body(color: primaryText),
                        decoration: InputDecoration(
                          hintText: 'Search banks...',
                          hintStyle: AppTypography.body(color: secondaryText),
                          prefixIcon: Icon(Icons.search, color: secondaryText),
                          filled: true,
                          fillColor: searchFill,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: accent, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onChanged: (value) {
                          setModalState(() {
                            if (value.isEmpty) {
                              filteredBanks = Banks.allSorted;
                            } else {
                              filteredBanks = Banks.allSorted
                                  .where((bank) =>
                                      bank.name.toLowerCase().contains(value.toLowerCase()) ||
                                      bank.shortName.toLowerCase().contains(value.toLowerCase()))
                                  .toList();
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      scrollController.dispose();
      searchController.dispose();
    });
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveCard,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF374151),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Text(
                widget.card != null ? 'Save Changes' : 'Confirm & Save',
                style: AppTypography.button(
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}

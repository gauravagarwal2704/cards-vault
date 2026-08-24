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
import '../services/card_background_storage.dart';
import '../widgets/bank_logo.dart';
import '../widgets/card_attachments.dart';
import '../widgets/card_background_picker.dart';
import '../widgets/card_background_preview_swiper.dart';
import '../widgets/card_background_surface.dart';
import '../widgets/card_network_logo.dart';
import '../widgets/group_picker_sheet.dart';
import '../widgets/wallet_card.dart';
import '../widgets/wallet_card_face.dart';
import '../utils/card_formatter.dart';
import '../utils/card_contrast.dart';
import '../utils/card_network_utils.dart';
import '../providers/theme_provider.dart';
import '../theme/app_motion.dart';
import '../theme/app_typography.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_design_system.dart';

enum CardEditInitialSection { cardDetails, additionalInformation }

class CardEditScreen extends StatefulWidget {
  final CardData? card;
  final OCRResult? ocrResult;
  final CardEditInitialSection initialSection;

  const CardEditScreen({
    super.key,
    this.card,
    this.ocrResult,
    this.initialSection = CardEditInitialSection.cardDetails,
  }) : assert(card != null || ocrResult != null);

  @override
  State<CardEditScreen> createState() => _CardEditScreenState();
}

class _CardEditScreenState extends State<CardEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _additionalInformationSectionKey = GlobalKey();
  final _cardStorage = SecureCardStorage();
  final _encryptionService = EncryptionService();
  final _attachmentStorage = CardAttachmentStorage();
  final _backgroundStorage = CardBackgroundStorage();
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
  CardBackgroundMode _backgroundMode = CardBackgroundMode.catalog;
  Color _customGradientStart = const Color(0xFF2563EB);
  Color _customGradientEnd = const Color(0xFF8B5CF6);
  double _customGradientAngle = 135;
  String? _customBackgroundImagePath;
  double _backgroundImageBlur = 0;
  String? _detectedCardType;
  bool _isLoading = false;
  bool _isInitialized = false;
  bool _didApplyInitialSection = false;
  Set<String> _existingCardholderNames = {};
  CardNetwork _detectedNetwork = CardNetwork.unknown;

  double get _effectiveBackgroundImageBlur =>
      (_backgroundMode == CardBackgroundMode.customImage &&
              _customBackgroundImagePath?.isNotEmpty == true) ||
          (_backgroundMode == CardBackgroundMode.catalog &&
              _selectedDesign?.style == CardDesignStyle.image)
      ? _backgroundImageBlur
      : 0;

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
          _selectedBank = card.bankId != null
              ? Banks.getById(card.bankId!)
              : null;
          _selectedGroup = group;
          _selectedDesign = card.designId != null
              ? CardDesigns.getById(card.designId!)
              : null;
          if (_selectedDesign != null) {
            _selectedStyle = _selectedDesign!.style;
          }
          _customGradientStart = Color(
            card.customGradientStartColor ?? 0xFF2563EB,
          );
          _customGradientEnd = Color(card.customGradientEndColor ?? 0xFF8B5CF6);
          _customGradientAngle = card.customGradientAngle;
          _customBackgroundImagePath = card.customBackgroundImagePath;
          _backgroundImageBlur = card.backgroundImageBlur;
          if (card.customBackgroundImagePath != null) {
            _backgroundMode = CardBackgroundMode.customImage;
          } else if (card.customGradientStartColor != null &&
              card.customGradientEndColor != null) {
            _backgroundMode = CardBackgroundMode.customGradient;
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
    _scheduleInitialSectionScroll();
  }

  void _scheduleInitialSectionScroll() {
    if (_didApplyInitialSection ||
        widget.initialSection != CardEditInitialSection.additionalInformation) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didApplyInitialSection) return;
      final targetContext = _additionalInformationSectionKey.currentContext;
      if (targetContext == null) return;

      _didApplyInitialSection = true;
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.08,
        duration: AppMotion.resolve(context, AppMotion.standard),
        curve: AppMotion.standardCurve,
      );
    });
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
    String cardNumber = _cardNumberController.text.replaceAll(
      RegExp(r'[\s\-]'),
      '',
    );
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

  Future<void> _saveCard() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    String? newlyStoredBackgroundPath;
    String? targetCardId;
    try {
      final cardNumber = _cardNumberController.text.replaceAll(' ', '');
      final expiry = _expiryController.text;
      final cardholder = _cardholderController.text.isEmpty
          ? null
          : _cardholderController.text;
      final cvv = _cvvController.text.isEmpty ? null : _cvvController.text;
      final nickname = _nicknameController.text.isEmpty
          ? null
          : _nicknameController.text;
      final accountNumber = _accountNumberController.text.isEmpty
          ? null
          : _accountNumberController.text;
      final ifscCode = _ifscCodeController.text.isEmpty
          ? null
          : _ifscCodeController.text;
      final upiId = _upiIdController.text.isEmpty
          ? null
          : _upiIdController.text;
      final notes = _notesController.text.isEmpty
          ? null
          : _notesController.text;
      final cardIdForSave =
          widget.card?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
      targetCardId = cardIdForSave;
      var persistedBackgroundPath =
          _backgroundMode == CardBackgroundMode.customImage
          ? _customBackgroundImagePath
          : null;
      final originalBackgroundPath = widget.card?.customBackgroundImagePath;
      if (persistedBackgroundPath != null &&
          persistedBackgroundPath != originalBackgroundPath) {
        newlyStoredBackgroundPath = await _backgroundStorage.saveBackground(
          cardIdForSave,
          File(persistedBackgroundPath),
        );
        persistedBackgroundPath = newlyStoredBackgroundPath;
      }

      if (widget.card != null && widget.card!.id != null) {
        final encryptedCardNumber = await _encryptionService.encrypt(
          cardNumber,
        );
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
        await _attachmentStorage.deleteAttachments(
          cardId,
          _removedAttachmentIds,
        );
        final newIds = await _attachmentStorage.saveAttachments(
          cardId,
          _pendingAttachmentFiles,
        );

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
          designId: _backgroundMode == CardBackgroundMode.catalog
              ? _selectedDesign?.id
              : null,
          customGradientStartColor:
              _backgroundMode == CardBackgroundMode.customGradient
              ? _customGradientStart.toARGB32()
              : null,
          customGradientEndColor:
              _backgroundMode == CardBackgroundMode.customGradient
              ? _customGradientEnd.toARGB32()
              : null,
          customGradientAngle: _customGradientAngle,
          customBackgroundImagePath: persistedBackgroundPath,
          backgroundImageBlur: _effectiveBackgroundImageBlur,
          clearDesign:
              _backgroundMode != CardBackgroundMode.catalog ||
              _selectedDesign == null,
          clearCustomGradient:
              _backgroundMode != CardBackgroundMode.customGradient,
          clearCustomBackgroundImage:
              _backgroundMode != CardBackgroundMode.customImage ||
              persistedBackgroundPath == null,
          notes: notes,
          attachmentIds: [..._existingAttachmentIds, ...newIds],
          groupId: _selectedGroup?.id,
          clearGroup: _selectedGroup == null,
        );

        await _cardStorage.updateCard(updatedCard);

        if (originalBackgroundPath != null &&
            originalBackgroundPath != persistedBackgroundPath) {
          await _backgroundStorage.deleteBackground(
            cardIdForSave,
            originalBackgroundPath,
          );
        }

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
          id: cardIdForSave,
          savedDate: DateTime.now(),
          readMethod: ReadMethod.camera,
          cardCategory: _cardCategory,
          bankId: _selectedBank?.id,
          cardNickname: nickname,
          designId: _backgroundMode == CardBackgroundMode.catalog
              ? _selectedDesign?.id
              : null,
          customGradientStartColor:
              _backgroundMode == CardBackgroundMode.customGradient
              ? _customGradientStart.toARGB32()
              : null,
          customGradientEndColor:
              _backgroundMode == CardBackgroundMode.customGradient
              ? _customGradientEnd.toARGB32()
              : null,
          customGradientAngle: _customGradientAngle,
          customBackgroundImagePath: persistedBackgroundPath,
          backgroundImageBlur: _effectiveBackgroundImageBlur,
          notes: notes,
          attachmentIds: const [],
          groupId: _selectedGroup?.id,
        );

        if (mounted) {
          Navigator.pop(context, card);
        }
      }
    } catch (e) {
      if (targetCardId != null && newlyStoredBackgroundPath != null) {
        await _backgroundStorage.deleteBackground(
          targetCardId,
          newlyStoredBackgroundPath,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save card: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: _buildSaveAction(),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            if (!wide) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: _buildEditorFields(includePreview: true),
                  ),
                ),
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 430,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      children: [
                        if (widget.ocrResult != null) ...[
                          _buildInfoBanner(),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        _buildPreviewCard(),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Preview updates as you edit',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: _buildEditorFields(includePreview: false),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildEditorFields({required bool includePreview}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (includePreview && widget.ocrResult != null) ...[
          _buildInfoBanner(),
          const SizedBox(height: AppSpacing.md),
        ],
        if (includePreview) ...[
          _buildPreviewCard(),
          const SizedBox(height: AppSpacing.xl),
        ],
        _buildSectionTitle('Card Information'),
        const SizedBox(height: AppSpacing.sm),
        _buildCardNumberField(),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(child: _buildExpiryField()),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: _buildCvvField()),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _buildCardholderField(),
        const SizedBox(height: AppSpacing.xl),
        _buildSectionTitle('Card Type'),
        const SizedBox(height: AppSpacing.sm),
        _buildCardCategorySelector(),
        const SizedBox(height: AppSpacing.xl),
        _buildSectionTitle('Bank'),
        const SizedBox(height: AppSpacing.sm),
        _buildBankSelector(),
        const SizedBox(height: AppSpacing.xl),
        _buildSectionTitle('Group'),
        const SizedBox(height: AppSpacing.sm),
        GroupSelectorField(
          selectedGroup: _selectedGroup,
          onChanged: (group) => setState(() => _selectedGroup = group),
        ),
        const SizedBox(height: AppSpacing.xl),
        _buildSectionTitle('Card Nickname'),
        const SizedBox(height: AppSpacing.sm),
        _buildNicknameField(),
        const SizedBox(height: AppSpacing.xl),
        _buildSectionTitle('Card Design'),
        const SizedBox(height: AppSpacing.sm),
        _buildCardBackgroundPicker(),
        const SizedBox(height: AppSpacing.xl),
        _buildSectionTitle(
          'Additional Information',
          key: _additionalInformationSectionKey,
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildAdditionalInfoFields(),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  Widget _buildInfoBanner() {
    final result = widget.ocrResult!;
    final isConfident = !result.needsReview;
    final confidence = (result.overallConfidence * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppStatusMessage(
          kind: isConfident ? AppStatusKind.success : AppStatusKind.warning,
          icon: isConfident
              ? Icons.verified_user_outlined
              : Icons.rate_review_outlined,
          title: isConfident
              ? 'High-confidence on-device scan'
              : 'Review the highlighted scan results',
          message:
              '$confidence% confidence'
              '${result.supportingFrames > 1 ? ' · agreed across ${result.supportingFrames} frames' : ''}'
              '${result.reviewWarnings.isEmpty ? '' : '\n${result.reviewWarnings.map((warning) => '• $warning').join('\n')}'}'
              '\nProcessed on this device. Source photos were discarded.',
        ),
      ],
    );
  }

  Widget _buildPreviewCard() {
    final themeProvider = context.watch<ThemeProvider>();
    final primaryColor =
        _selectedDesign?.primaryColor ??
        _selectedBank?.primaryColor ??
        themeProvider.getPrimaryColor();
    final secondaryColor =
        _selectedDesign?.secondaryColor ??
        _selectedBank?.secondaryColor ??
        themeProvider.getPrimaryContainerColor();
    final foregroundColor = switch (_backgroundMode) {
      CardBackgroundMode.catalog =>
        _selectedDesign?.foregroundColor ??
            CardContrast.bestForeground([primaryColor, secondaryColor]),
      CardBackgroundMode.customGradient => CardContrast.bestForeground([
        _customGradientStart,
        _customGradientEnd,
      ]),
      CardBackgroundMode.customImage => CardContrast.ivory,
    };
    final faceBackgroundColor =
        _backgroundMode == CardBackgroundMode.customGradient
        ? _customGradientStart
        : primaryColor;

    return CardBackgroundPreviewSwiper(
      enabled: _backgroundMode == CardBackgroundMode.catalog,
      backgroundKey:
          '${_backgroundMode.name}:${_selectedDesign?.id ?? 'default'}',
      onCycle: _cyclePreviewBackground,
      child: AspectRatio(
        aspectRatio: 1.586,
        child: CardBackgroundSurface(
          design: _backgroundMode == CardBackgroundMode.catalog
              ? _selectedDesign
              : null,
          customGradientStartColor:
              _backgroundMode == CardBackgroundMode.customGradient
              ? _customGradientStart.toARGB32()
              : null,
          customGradientEndColor:
              _backgroundMode == CardBackgroundMode.customGradient
              ? _customGradientEnd.toARGB32()
              : null,
          customGradientAngle: _customGradientAngle,
          customBackgroundImagePath:
              _backgroundMode == CardBackgroundMode.customImage
              ? _customBackgroundImagePath
              : null,
          backgroundImageBlur: _effectiveBackgroundImageBlur,
          fallbackPrimaryColor: primaryColor,
          fallbackSecondaryColor: secondaryColor,
          borderRadius: BorderRadius.circular(20),
          child: WalletCardFace(
            bank: _selectedBank,
            network: _detectedNetwork,
            categoryName: _cardCategory == CardCategory.credit
                ? 'Credit'
                : 'Debit',
            nickname: _nicknameController.text,
            cardNumber: _cardNumberController.text.isEmpty
                ? CardData.hiddenCardNumber
                : _cardNumberController.text,
            cardholderName: _cardholderController.text.isEmpty
                ? 'YOUR NAME'
                : _cardholderController.text,
            expiryDate: _expiryController.text.isEmpty
                ? 'MM/YY'
                : _expiryController.text,
            backgroundColor: faceBackgroundColor,
            foregroundColor: foregroundColor,
          ),
        ),
      ),
    );
  }

  void _cyclePreviewBackground(int direction) {
    if (_backgroundMode != CardBackgroundMode.catalog) return;

    setState(() {
      _selectedDesign = CardDesigns.cycle(
        style: _selectedStyle,
        currentId: _selectedDesign?.id,
        direction: direction,
      );
    });
  }

  Widget _buildSectionTitle(String title, {Key? key}) {
    final themeProvider = context.watch<ThemeProvider>();
    return Text(
      title,
      key: key,
      style: AppTypography.title(color: themeProvider.getPrimaryTextColor()),
    );
  }

  Widget _buildCardNumberField() {
    final themeProvider = context.watch<ThemeProvider>();

    return TextFormField(
      controller: _cardNumberController,
      keyboardType: TextInputType.number,
      inputFormatters: [CardNumberFormatter(network: _detectedNetwork)],
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
      style: AppTypography.bodyLarge(color: themeProvider.getPrimaryTextColor())
          .copyWith(letterSpacing: 0.8),
      onChanged: (value) {
        final cleaned = value.replaceAll(' ', '');
        final newNetwork = CardNetworkUtils.detectNetwork(cleaned);
        setState(() => _detectedNetwork = newNetwork);
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
      style: AppTypography.bodyLarge(
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
      style: AppTypography.bodyLarge(
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
        return _existingCardholderNames.where(
          (name) =>
              name.toLowerCase().contains(textEditingValue.text.toLowerCase()),
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
                constraints: const BoxConstraints(
                  maxHeight: 200,
                  maxWidth: 400,
                ),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
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
    final scheme = Theme.of(context).colorScheme;

    return InputDecoration(
      hintText: hint,
      hintStyle: AppTypography.style(color: scheme.onSurfaceVariant),
      prefixIcon: icon != null
          ? Icon(icon, color: scheme.onSurfaceVariant)
          : null,
      filled: true,
      fillColor: Colors.transparent,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outline, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outline, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.error, width: 1.5),
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
    final isSelected = _cardCategory == category;
    return ChoiceChip(
      selected: isSelected,
      label: SizedBox(
        width: double.infinity,
        child: Text(label, textAlign: TextAlign.center),
      ),
      onSelected: (_) => setState(() => _cardCategory = category),
    );
  }

  Widget _buildBankSelector() {
    final themeProvider = context.watch<ThemeProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Popular Banks',
          style: AppTypography.caption(
            color: themeProvider.getSecondaryTextColor(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: Banks.popular.map((bank) => _buildBankChip(bank)).toList(),
        ),
        const SizedBox(height: 16),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: _showBankSelectionModal,
            leading: _selectedBank == null
                ? const Icon(Icons.account_balance_outlined)
                : BankLogo(bank: _selectedBank, size: 24, useSmall: true),
            title: Text(_selectedBank?.name ?? 'Select bank'),
            trailing: const Icon(Icons.arrow_drop_down),
          ),
        ),
      ],
    );
  }

  Widget _buildBankChip(BankInfo bank) {
    final isSelected = _selectedBank?.id == bank.id;
    final scheme = Theme.of(context).colorScheme;
    final selectedBackground = Color.alphaBlend(
      bank.primaryColor.withValues(
        alpha: scheme.brightness == Brightness.dark ? 0.28 : 0.14,
      ),
      scheme.surfaceContainerHighest,
    );

    return ChoiceChip(
      selected: isSelected,
      avatar: BankLogo(bank: bank, size: 18, useSmall: true),
      label: Text(bank.shortName),
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: selectedBackground,
      showCheckmark: false,
      side: BorderSide(
        color: isSelected ? bank.primaryColor : scheme.outlineVariant,
        width: isSelected ? 1.5 : 1,
      ),
      onSelected: (_) => setState(() => _selectedBank = bank),
    );
  }

  Widget _buildCardBackgroundPicker() {
    return CardBackgroundPicker(
      mode: _backgroundMode,
      selectedStyle: _selectedStyle,
      selectedDesign: _selectedDesign,
      gradientStart: _customGradientStart,
      gradientEnd: _customGradientEnd,
      gradientAngle: _customGradientAngle,
      customImagePath: _customBackgroundImagePath,
      backgroundImageBlur: _backgroundImageBlur,
      onModeChanged: (mode) => setState(() => _backgroundMode = mode),
      onStyleChanged: (style) {
        setState(() {
          _selectedStyle = style;
          _selectedDesign = null;
        });
      },
      onDesignChanged: (design) => setState(() => _selectedDesign = design),
      onGradientChanged: (start, end) {
        setState(() {
          _customGradientStart = start;
          _customGradientEnd = end;
        });
      },
      onGradientAngleChanged: (angle) =>
          setState(() => _customGradientAngle = angle),
      onCustomImageChanged: (path) =>
          setState(() => _customBackgroundImagePath = path),
      onBackgroundImageBlurChanged: (blur) =>
          setState(() => _backgroundImageBlur = blur),
    );
  }

  Widget _buildAdditionalInfoFields() {
    return Column(
      children: [
        TextFormField(
          controller: _accountNumberController,
          decoration: _inputDecoration(
            'Bank Account Number',
            Icons.account_balance_wallet,
          ),
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
            final removed = _existingAttachmentIds.where(
              (id) => !ids.contains(id),
            );
            setState(() {
              _removedAttachmentIds.addAll(removed);
              _existingAttachmentIds = ids;
            });
          },
          onPendingChanged: (files) =>
              setState(() => _pendingAttachmentFiles = files),
        ),
      ],
    );
  }

  void _showBankSelectionModal() {
    final TextEditingController searchController = TextEditingController();
    List<BankInfo> filteredBanks = Banks.allSorted;
    const double bankTileExtent = 60;
    final selectedIndex = filteredBanks.indexWhere(
      (b) => b.id == _selectedBank?.id,
    );
    final scrollController = ScrollController(
      initialScrollOffset: selectedIndex > 0
          ? selectedIndex * bankTileExtent
          : 0,
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
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
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
                              style: AppTypography.sectionTitle(
                                color: primaryText,
                              ),
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
                            leading: BankLogo(
                              bank: bank,
                              size: 32,
                              useSmall: true,
                            ),
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
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (value) {
                          setModalState(() {
                            if (value.isEmpty) {
                              filteredBanks = Banks.allSorted;
                            } else {
                              filteredBanks = Banks.allSorted
                                  .where(
                                    (bank) =>
                                        bank.name.toLowerCase().contains(
                                          value.toLowerCase(),
                                        ) ||
                                        bank.shortName.toLowerCase().contains(
                                          value.toLowerCase(),
                                        ),
                                  )
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

  Widget _buildSaveAction() {
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      key: const ValueKey('card-editor-save'),
      onPressed: _isLoading ? null : _saveCard,
      child: _isLoading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: scheme.primary,
                strokeWidth: 2,
              ),
            )
          : const Text('Save'),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/card_data.dart';
import '../models/card_group.dart';
import '../data/banks.dart';
import '../data/card_designs.dart';
import '../services/card_attachment_storage.dart';
import '../services/card_background_storage.dart';
import '../services/secure_card_storage.dart';
import '../widgets/bank_logo.dart';
import '../widgets/card_attachments.dart';
import '../widgets/card_background_picker.dart';
import '../widgets/card_background_preview_swiper.dart';
import '../widgets/card_background_surface.dart';
import '../widgets/group_picker_sheet.dart';
import '../widgets/card_network_logo.dart';
import '../widgets/wallet_card.dart';
import '../utils/card_formatter.dart';
import '../utils/card_contrast.dart';
import '../utils/card_network_utils.dart';
import '../providers/theme_provider.dart';
import '../theme/app_typography.dart';
import '../theme/app_spacing.dart';

class ManualAddCardScreen extends StatefulWidget {
  const ManualAddCardScreen({super.key});

  @override
  State<ManualAddCardScreen> createState() => _ManualAddCardScreenState();
}

class _ManualAddCardScreenState extends State<ManualAddCardScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cardNumberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();
  final _cardholderController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _cardStorage = SecureCardStorage();
  final _attachmentStorage = CardAttachmentStorage();
  final _backgroundStorage = CardBackgroundStorage();
  List<File> _pendingAttachmentFiles = [];

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
  bool _isLoading = false;
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
    _loadExistingCardholders();
  }

  @override
  void dispose() {
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _cardholderController.dispose();
    _nicknameController.dispose();
    super.dispose();
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

  Future<void> _saveCard() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    String? savedBackgroundPath;
    String? newCardId;
    try {
      final cardNumber = _cardNumberController.text.replaceAll(' ', '');
      final cardIdForSave = const Uuid().v4();
      newCardId = cardIdForSave;
      if (_backgroundMode == CardBackgroundMode.customImage &&
          _customBackgroundImagePath != null) {
        savedBackgroundPath = await _backgroundStorage.saveBackground(
          cardIdForSave,
          File(_customBackgroundImagePath!),
        );
      }
      final card = await CardData.fromPlaintext(
        cardNumber: cardNumber,
        expiryDate: _expiryController.text,
        cardholderName: _cardholderController.text.isEmpty
            ? null
            : _cardholderController.text,
        cvv: _cvvController.text.isEmpty ? null : _cvvController.text,
        cardType: _detectCardType(cardNumber),
        id: cardIdForSave,
        savedDate: DateTime.now(),
        readMethod: ReadMethod.manual,
        cardCategory: _cardCategory,
        bankId: _selectedBank?.id,
        cardNickname: _nicknameController.text.isEmpty
            ? null
            : _nicknameController.text,
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
        customBackgroundImagePath: savedBackgroundPath,
        backgroundImageBlur: _effectiveBackgroundImageBlur,
        groupId: _selectedGroup?.id,
      );

      final cardId = await _cardStorage.saveCard(card);

      if (_pendingAttachmentFiles.isNotEmpty) {
        final attachmentIds = await _attachmentStorage.saveAttachments(
          cardId,
          _pendingAttachmentFiles,
        );
        await _cardStorage.updateCard(
          card.copyWith(id: cardId, attachmentIds: attachmentIds),
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (newCardId != null && savedBackgroundPath != null) {
        await _backgroundStorage.deleteBackground(
          newCardId,
          savedBackgroundPath,
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

  String _detectCardType(String cardNumber) =>
      CardNetworkUtils.cardTypeFromNumber(cardNumber);

  String _formatCardNumber(String text) {
    text = text.replaceAll(' ', '');
    return CardNetworkUtils.formatCardNumber(text, _detectedNetwork);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

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
          'Add Card',
          style: AppTypography.appBarTitle(
            color: themeProvider.getPrimaryTextColor(),
          ),
        ),
        centerTitle: true,
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
      bottomNavigationBar: SafeArea(
        top: false,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Align(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: _buildSaveButton(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditorFields({required bool includePreview}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        _buildSectionTitle('Photos'),
        const SizedBox(height: AppSpacing.sm),
        CardAttachmentsEditor(
          cardId: null,
          existingIds: const [],
          pendingFiles: _pendingAttachmentFiles,
          onExistingChanged: (_) {},
          onPendingChanged: (files) =>
              setState(() => _pendingAttachmentFiles = files),
        ),
        const SizedBox(height: AppSpacing.xxl),
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
    final secondaryForeground = CardContrast.secondary(foregroundColor);
    final tertiaryForeground = CardContrast.tertiary(foregroundColor);

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
          child: Padding(
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
                              _cardCategory == CardCategory.credit
                                  ? 'Credit'
                                  : 'Debit',
                              style: AppTypography.cardName(
                                color: foregroundColor,
                              ),
                            ),
                            Text(
                              'Card',
                              style: AppTypography.cardNameLight(
                                color: secondaryForeground,
                              ),
                            ),
                          ],
                        ),
                        if (_nicknameController.text.isNotEmpty)
                          Text(
                            _nicknameController.text,
                            style: AppTypography.caption(
                              fontSize: 11,
                              color: tertiaryForeground,
                            ),
                          ),
                      ],
                    ),
                    Icon(
                      Icons.contactless,
                      color: secondaryForeground,
                      size: 24,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  _cardNumberController.text.isEmpty
                      ? '**** **** **** ****'
                      : _formatCardNumber(_cardNumberController.text),
                  style: AppTypography.mono(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: foregroundColor,
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
                      style: AppTypography.caption(color: secondaryForeground)
                          .copyWith(fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    Text(
                      _expiryController.text.isEmpty
                          ? 'MM/YY'
                          : _expiryController.text,
                      style: AppTypography.mono(
                        fontSize: 12,
                        color: secondaryForeground,
                      ),
                    ),
                  ],
                ),
              ],
            ),
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

  Widget _buildSectionTitle(String title) {
    final themeProvider = context.watch<ThemeProvider>();
    return Text(
      title,
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
    final themeProvider = context.watch<ThemeProvider>();

    return TextFormField(
      controller: _nicknameController,
      decoration: _inputDecoration('e.g., ICICI Coral, Axis Priority', null),
      style: AppTypography.bodyLarge(
        color: themeProvider.getPrimaryTextColor(),
      ),
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
    return ChoiceChip(
      selected: isSelected,
      avatar: BankLogo(bank: bank, size: 18, useSmall: true),
      label: Text(bank.shortName),
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

  Widget _buildSaveButton() {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        onPressed: _isLoading ? null : _saveCard,
        icon: _isLoading
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: scheme.onPrimary,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.check_rounded),
        label: const Text('Save card'),
      ),
    );
  }
}

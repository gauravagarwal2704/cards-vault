import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/card_data.dart';
import '../models/card_group.dart';
import '../services/card_group_storage.dart';
import '../services/secure_card_storage.dart';
import '../services/ocr_service.dart';
import '../providers/card_view_provider.dart';
import '../providers/nfc_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/card_tiles_grid.dart';
import '../widgets/group_picker_sheet.dart';
import '../widgets/stacked_card_grid.dart';
import '../widgets/infinite_card_deck.dart';
import '../widgets/floating_add_menu.dart';
import '../widgets/bank_logo.dart';
import '../data/banks.dart';
import '../utils/image_crop_helper.dart';
import '../utils/image_utils.dart';
import '../utils/nfc_availability_prompt.dart';
import 'card_detail_screen.dart';
import 'manual_add_card_screen.dart';
import 'card_camera_screen.dart';
import 'card_edit_screen.dart';
import 'nfc_scan_screen.dart';
import 'settings_screen.dart';
import '../theme/app_typography.dart';

class SavedCardsScreen extends StatefulWidget {
  const SavedCardsScreen({super.key});

  @override
  State<SavedCardsScreen> createState() => _SavedCardsScreenState();
}

class _SavedCardsScreenState extends State<SavedCardsScreen>
    with TickerProviderStateMixin {
  final SecureCardStorage _cardStorage = SecureCardStorage();
  final CardGroupStorage _groupStorage = CardGroupStorage();
  final OCRService _ocrService = OCRService();
  List<CardData> _cards = [];
  List<CardGroup> _groups = [];
  bool _isLoading = true;
  bool _showAddOptions = false;
  bool _isProcessingImage = false;
  
  Set<CardCategory>? _selectedCategories;
  Set<String>? _selectedCardholderNames;
  Set<String>? _selectedBankIds;
  Set<String>? _selectedNicknames;
  Set<String>? _selectedGroupIds;
  
  Set<String> _allCardholderNames = {};
  Map<String, String> _cardIdToCardholderName = {}; // Maps card ID to decrypted cardholder name
  
  Set<String> get _allBankIds {
    return _cards
        .where((c) => c.bankId != null)
        .map((c) => c.bankId!)
        .toSet();
  }
  
  Set<String> get _allNicknames {
    return _cards
        .where((c) => c.cardNickname != null && c.cardNickname!.isNotEmpty)
        .map((c) => c.cardNickname!)
        .toSet();
  }

  late AnimationController _blurController;
  late AnimationController _optionsController;
  late Animation<double> _blurAnimation;
  late List<Animation<double>> _slideAnimations;
  late List<Animation<double>> _fadeAnimations;

  @override
  void initState() {
    super.initState();
    _loadCards();

    _blurController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _blurAnimation = CurvedAnimation(
      parent: _blurController,
      curve: Curves.easeOut,
    );

    _optionsController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _slideAnimations = List.generate(3, (index) {
      final start = index * 0.15;
      final end = start + 0.6;
      return Tween<double>(begin: 60.0, end: 0.0).animate(
        CurvedAnimation(
          parent: _optionsController,
          curve: Interval(start, end.clamp(0.0, 1.0), curve: Curves.easeOutBack),
        ),
      );
    });

    _fadeAnimations = List.generate(3, (index) {
      final start = index * 0.15;
      final end = start + 0.5;
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _optionsController,
          curve: Interval(start, end.clamp(0.0, 1.0), curve: Curves.easeOut),
        ),
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NfcProvider>().checkNfcAvailability();
    });
  }

  @override
  void dispose() {
    _blurController.dispose();
    _optionsController.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final cards = await _cardStorage.loadCards();
      final groups = await _groupStorage.loadGroups();
      final names = await Future.wait(
        cards.map((c) => c.getDecryptedCardholderName()).toList(),
      );

      final cardIdToName = <String, String>{};
      for (int i = 0; i < cards.length; i++) {
        if (cards[i].id != null && names[i] != null) {
          cardIdToName[cards[i].id!] = names[i]!;
        }
      }

      if (!mounted) return;
      setState(() {
        _cards = cards;
        _groups = groups;
        _allCardholderNames = names.whereType<String>().toSet();
        _cardIdToCardholderName = cardIdToName;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load cards: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  List<CardData> _getFilteredCards() {
    var filtered = _cards;
    
    if (_selectedCategories != null && _selectedCategories!.isNotEmpty) {
      filtered = filtered.where((c) => _selectedCategories!.contains(c.cardCategory)).toList();
    }
    
    if (_selectedCardholderNames != null && _selectedCardholderNames!.isNotEmpty) {
      filtered = filtered.where((card) {
        if (card.id == null) return false;
        final cardholderName = _cardIdToCardholderName[card.id];
        return cardholderName != null && _selectedCardholderNames!.contains(cardholderName);
      }).toList();
    }
    
    if (_selectedBankIds != null && _selectedBankIds!.isNotEmpty) {
      filtered = filtered.where((c) => 
        c.bankId != null && _selectedBankIds!.contains(c.bankId)
      ).toList();
    }
    
    if (_selectedNicknames != null && _selectedNicknames!.isNotEmpty) {
      filtered = filtered.where((c) => 
        c.cardNickname != null && _selectedNicknames!.contains(c.cardNickname)
      ).toList();
    }
    
    if (_selectedGroupIds != null && _selectedGroupIds!.isNotEmpty) {
      filtered = filtered.where((c) => 
        c.groupId != null && _selectedGroupIds!.contains(c.groupId)
      ).toList();
    }
    
    return filtered;
  }
  
  void _clearFilters() {
    setState(() {
      _selectedCategories = null;
      _selectedCardholderNames = null;
      _selectedBankIds = null;
      _selectedNicknames = null;
      _selectedGroupIds = null;
    });
  }
  
  bool get _hasActiveFilters =>
      (_selectedCategories != null && _selectedCategories!.isNotEmpty) ||
      (_selectedCardholderNames != null && _selectedCardholderNames!.isNotEmpty) ||
      (_selectedBankIds != null && _selectedBankIds!.isNotEmpty) ||
      (_selectedNicknames != null && _selectedNicknames!.isNotEmpty) ||
      (_selectedGroupIds != null && _selectedGroupIds!.isNotEmpty);
  
  int get _activeFilterCount {
    int count = 0;
    if (_selectedCategories != null) count += _selectedCategories!.length;
    if (_selectedBankIds != null) count += _selectedBankIds!.length;
    if (_selectedCardholderNames != null) count += _selectedCardholderNames!.length;
    if (_selectedNicknames != null) count += _selectedNicknames!.length;
    if (_selectedGroupIds != null) count += _selectedGroupIds!.length;
    return count;
  }

  Future<void> _shareCard(CardData card) async {
    final bank = card.bankId != null ? Banks.getById(card.bankId!) : null;
    final cardholderName = card.id != null ? _cardIdToCardholderName[card.id] : null;
    
    final cardInfo = StringBuffer();
    cardInfo.writeln('Card Details:');
    cardInfo.writeln('');
    
    if (bank != null) {
      cardInfo.writeln('Bank: ${bank.name}');
    }
    
    cardInfo.writeln('Type: ${card.categoryName}');
    
    if (card.cardNickname != null && card.cardNickname!.isNotEmpty) {
      cardInfo.writeln('Nickname: ${card.cardNickname}');
    }
    
    cardInfo.writeln('Card: ${card.maskedCardNumber}');
    
    if (cardholderName != null && cardholderName.isNotEmpty) {
      cardInfo.writeln('Cardholder: $cardholderName');
    }
    
    cardInfo.writeln('');
    cardInfo.writeln('⚠️ Shared from Cards Wallet');
    cardInfo.writeln('Note: Keep your card information secure');
    
    try {
      await Share.share(
        cardInfo.toString(),
        subject: 'Card Information',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteCard(CardData card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Card'),
        content: Text('Delete card ending in ${card.lastFourDigits}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && card.id != null) {
      try {
        await _cardStorage.deleteCard(card.id!);
        await _loadCards();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Card deleted'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
  
  void _onCardTap(CardData card) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CardDetailScreen(
          card: card,
          cardIndex: _cards.indexOf(card),
        ),
      ),
    );

    if (result == true) {
      await _loadCards();
    }
  }

  /// Long press is the quickest way to move a card between groups without
  /// opening the full edit screen.
  Future<void> _changeCardGroup(CardData card) async {
    if (card.id == null) return;

    final selection = await showGroupPickerSheet(
      context,
      selectedGroupId: card.groupId,
    );
    if (selection == null) return;

    await _cardStorage.updateCard(
      card.copyWith(
        groupId: selection.group?.id,
        clearGroup: selection.group == null,
      ),
    );
    await _loadCards();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          selection.group == null
              ? 'Removed from group'
              : 'Moved to ${selection.group!.name}',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _toggleAddOptions() {
    setState(() {
      _showAddOptions = !_showAddOptions;
    });
    if (_showAddOptions) {
      _blurController.forward();
      _optionsController.forward();
    } else {
      _optionsController.reverse();
      _blurController.reverse();
    }
  }

  void _handleAddOption(AddCardOption option) async {
    _toggleAddOptions();

    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;

    switch (option) {
      case AddCardOption.nfc:
        final nfcReady = await ensureNfcReady(context);
        if (!mounted || !nfcReady) break;
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (context) => const NfcScanScreen()),
        );
        if (result == true && mounted) _loadCards();
        break;
      case AddCardOption.scan:
        await _handleCameraScan();
        break;
      case AddCardOption.manual:
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ManualAddCardScreen()),
        );
        if (mounted) _loadCards();
        break;
    }
  }

  Future<void> _handleCameraScan() async {
    final capturedPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const CardCameraScreen()),
    );

    if (capturedPath == null || !mounted) return;

    // Cropping to just the card measurably improves recognition; if the user
    // skips it we fall back to the untouched image.
    final cropped = await cropImageFile(
      context,
      capturedPath,
      toolbarTitle: 'Crop to card',
      startWithCardRatio: true,
    );
    if (!mounted) return;

    final imagePath = cropped?.path ?? capturedPath;

    setState(() => _isProcessingImage = true);

    try {
      final quality = await ImageUtils.validateImageQuality(imagePath);
      if (!mounted) return;

      if (!quality.isGoodQuality) {
        setState(() => _isProcessingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(quality.warning ??
                'Image quality is poor. Please try a clearer photo.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final ocrResult = await _ocrService.processImage(imagePath);

      if (!mounted) return;

      setState(() => _isProcessingImage = false);

      if (ocrResult.cardNumber == null || ocrResult.cardNumber!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not detect card number. Please try again or add manually.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final cardData = await Navigator.push<CardData>(
        context,
        MaterialPageRoute(
          builder: (context) => CardEditScreen(ocrResult: ocrResult),
        ),
      );

      if (cardData != null && mounted) {
        await _cardStorage.saveCard(cardData);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Card saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadCards();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildCardsView() {
    final cards = _getFilteredCards();

    switch (context.watch<CardViewProvider>().viewMode) {
      case CardViewMode.carousel:
        return InfiniteCardDeck(
          cards: cards,
          onCardTap: _onCardTap,
          onCardLongPress: _deleteCard,
          onCardShare: _shareCard,
          onCardDelete: _deleteCard,
        );
      case CardViewMode.grid:
        return CardTilesGrid(
          cards: cards,
          onCardTap: _onCardTap,
          onCardLongPress: _changeCardGroup,
        );
      case CardViewMode.stackedGrid:
        final stackBy = context.watch<CardViewProvider>().stackBy;
        return StackedCardGrid(
          stacks: _buildStacks(cards, stackBy),
          axisKey: stackBy.name,
          canGroupByDrag: stackBy == CardStackBy.custom,
          onCardTap: _onCardTap,
          onCardLongPress: _changeCardGroup,
          onDropOnStack: _handleDropOnStack,
        );
    }
  }

  /// A card was dragged onto [target]: either an existing group, which it joins,
  /// or another loose card, which turns the pair into a brand new group.
  Future<void> _handleDropOnStack(CardData card, CardStack target) async {
    if (card.id == null) return;

    if (target.groupId != null) {
      await _cardStorage.updateCard(card.copyWith(groupId: target.groupId));
      await _loadCards();
      _showGroupedSnackBar(target.title);
      return;
    }

    if (!target.isLooseCard) return;

    final partner = target.cards.first;
    final name = await showGroupNameDialog(
      context,
      title: 'New Group',
      initialValue: _suggestedGroupName(card, partner),
    );
    if (name == null || name.isEmpty) return;

    final group = await _groupStorage.createGroup(name);
    await _cardStorage.updateCard(card.copyWith(groupId: group.id));
    if (partner.id != null) {
      await _cardStorage.updateCard(partner.copyWith(groupId: group.id));
    }
    await _loadCards();
    _showGroupedSnackBar(group.name);
  }

  /// Two cards from the same bank almost always want that bank's name, which
  /// saves the most common bit of typing. Anything else is left to the user.
  String? _suggestedGroupName(CardData a, CardData b) {
    if (a.bankId == null || a.bankId != b.bankId) return null;
    return Banks.getById(a.bankId!)?.name;
  }

  void _showGroupedSnackBar(String groupName) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Moved to $groupName'),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// Buckets cards by the chosen axis. Cards with no value on that axis land in
  /// a trailing catch-all stack so nothing can go missing from the grid.
  List<CardStack> _buildStacks(List<CardData> cards, CardStackBy axis) {
    const unassignedKey = '__unassigned__';
    final buckets = <String, List<CardData>>{};
    final titles = <String, String>{};
    final bankIds = <String, String>{};
    final icons = <String, IconData>{};

    for (final card in cards) {
      final ({String key, String title}) bucket = switch (axis) {
        CardStackBy.bank => (
            key: card.bankId ?? unassignedKey,
            title: card.bankId != null
                ? (Banks.getById(card.bankId!)?.name ?? card.bankId!)
                : 'No bank',
          ),
        CardStackBy.type => (
            key: card.cardCategory.name,
            title: card.categoryName,
          ),
        CardStackBy.cardholder => _cardholderBucket(card, unassignedKey),
        CardStackBy.custom => _customGroupBucket(card, unassignedKey),
      };

      buckets.putIfAbsent(bucket.key, () => []).add(card);
      titles[bucket.key] = bucket.title;

      if (axis == CardStackBy.bank && card.bankId != null) {
        bankIds[bucket.key] = card.bankId!;
      } else if (axis == CardStackBy.type) {
        icons[bucket.key] = card.cardCategory == CardCategory.credit
            ? Icons.credit_card
            : Icons.credit_card_outlined;
      }
    }

    final stacks = buckets.entries
        .map((entry) => CardStack(
              key: entry.key,
              title: titles[entry.key]!,
              cards: entry.value,
              bankId: bankIds[entry.key],
              groupId: axis == CardStackBy.custom && entry.key != unassignedKey
                  ? entry.key
                  : null,
              icon: icons[entry.key],
            ))
        .toList();

    stacks.sort((a, b) {
      if (a.key == unassignedKey) return 1;
      if (b.key == unassignedKey) return -1;
      final byCount = b.cards.length.compareTo(a.cards.length);
      return byCount != 0 ? byCount : a.title.compareTo(b.title);
    });

    return axis == CardStackBy.custom
        ? _explodeLooseCards(stacks, unassignedKey)
        : stacks;
  }

  /// Under the custom axis, ungrouped cards are shown as individual tiles rather
  /// than collected into one bucket, so that a card can be dragged onto another
  /// card to form a group. The sort above already leaves them last.
  List<CardStack> _explodeLooseCards(
    List<CardStack> stacks,
    String unassignedKey,
  ) {
    final result = <CardStack>[];

    for (final stack in stacks) {
      if (stack.key != unassignedKey) {
        result.add(stack);
        continue;
      }

      for (final card in stack.cards) {
        final nickname = card.cardNickname;
        result.add(CardStack(
          key: card.id ?? 'card-${card.lastFourDigits}',
          title: nickname != null && nickname.isNotEmpty
              ? nickname
              : card.categoryName,
          cards: [card],
        ));
      }
    }

    return result;
  }

  ({String key, String title}) _cardholderBucket(
    CardData card,
    String unassignedKey,
  ) {
    final name = card.id != null ? _cardIdToCardholderName[card.id] : null;
    if (name == null || name.isEmpty) {
      return (key: unassignedKey, title: 'No cardholder');
    }
    return (key: name, title: name);
  }

  ({String key, String title}) _customGroupBucket(
    CardData card,
    String unassignedKey,
  ) {
    if (card.groupId == null) {
      return (key: unassignedKey, title: 'Ungrouped');
    }
    final group = _groups.firstWhere(
      (g) => g.id == card.groupId,
      orElse: () => CardGroup(
        id: unassignedKey,
        name: 'Ungrouped',
        createdAt: DateTime.now(),
      ),
    );
    return (key: group.id, title: group.name);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    
    return Scaffold(
      backgroundColor: themeProvider.getBackgroundColor(),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(context),
                if (context.watch<CardViewProvider>().viewMode ==
                        CardViewMode.stackedGrid &&
                    _cards.isNotEmpty)
                  _buildStackByPills(),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _cards.isEmpty
                          ? _buildEmptyState()
                          : _getFilteredCards().isEmpty
                              ? _buildNoResultsState()
                              : _buildCardsView(),
                ),
                if (context.watch<CardViewProvider>().viewMode ==
                    CardViewMode.carousel)
                  const SizedBox(height: 100),
              ],
            ),
            if (_showAddOptions) _buildBlurOverlay(),
            if (_isProcessingImage) _buildProcessingOverlay(),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomSection(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlurOverlay() {
    return AnimatedBuilder(
      animation: _blurAnimation,
      builder: (context, child) {
        return GestureDetector(
          onTap: _toggleAddOptions,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 8 * _blurAnimation.value,
              sigmaY: 8 * _blurAnimation.value,
            ),
            child: Container(
              color: Colors.black.withOpacity(0.3 * _blurAnimation.value),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProcessingOverlay() {
    final themeProvider = context.watch<ThemeProvider>();
    return Container(
      color: Colors.black54,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    themeProvider.getPrimaryColor(),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Processing Card...',
                  style: AppTypography.title(color: Colors.black87),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSection() {
    final themeProvider = context.watch<ThemeProvider>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showAddOptions) _buildPillOptions(),
          GestureDetector(
            onTap: _toggleAddOptions,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: themeProvider.isDarkMode
                    ? (_showAddOptions ? Colors.grey.shade300 : Colors.white)
                    : (_showAddOptions ? Colors.grey.shade700 : Colors.black),
                border: Border.all(
                  color: themeProvider.isDarkMode
                      ? (_showAddOptions ? Colors.grey.shade300 : Colors.white)
                      : (_showAddOptions ? Colors.grey.shade700 : Colors.black),
                  width: 1.5,
                ),
              ),
              child: AnimatedRotation(
                turns: _showAddOptions ? 0.125 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.add,
                  color: themeProvider.isDarkMode ? Colors.black : Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Add Card',
            style: AppTypography.caption(
              color: themeProvider.getSecondaryTextColor(),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillOptions() {
    final themeProvider = context.watch<ThemeProvider>();
    final options = <_OptionData>[
      _OptionData(
        icon: Icons.edit_outlined,
        label: 'Add Manually',
        color: themeProvider.getPrimaryColor(),
        option: AddCardOption.manual,
      ),
      _OptionData(
        icon: Icons.camera_alt_outlined,
        label: 'Scan Card',
        color: const Color(0xFF10B981),
        option: AddCardOption.scan,
      ),
      _OptionData(
        icon: Icons.contactless_outlined,
        label: 'Add via NFC',
        color: const Color(0xFF0EA5E9),
        option: AddCardOption.nfc,
      ),
    ];

    return AnimatedBuilder(
      animation: _optionsController,
      builder: (context, child) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(options.length, (index) {
            final opt = options[index];
            final animIndex = options.length - 1 - index;
            final slideAnim = _slideAnimations[animIndex % _slideAnimations.length];
            final fadeAnim = _fadeAnimations[animIndex % _fadeAnimations.length];

            return Transform.translate(
              offset: Offset(0, slideAnim.value),
              child: Opacity(
                opacity: fadeAnim.value.clamp(0.0, 1.0),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: _buildPillOption(
                    icon: opt.icon,
                    label: opt.label,
                    color: opt.color,
                    onTap: () => _handleAddOption(opt.option),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildPillOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF3A3A3C),
              const Color(0xFF2C2C2E),
              const Color(0xFF1C1C1E),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
            BoxShadow(
              color: Colors.white.withOpacity(0.05),
              blurRadius: 1,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTypography.label(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewModeButton(ThemeProvider themeProvider) {
    final viewProvider = context.watch<CardViewProvider>();

    return PopupMenuButton<CardViewMode>(
      tooltip: 'Change view',
      icon: Icon(
        viewProvider.viewMode.icon,
        color: themeProvider.getPrimaryTextColor(),
        size: 26,
      ),
      onSelected: viewProvider.setViewMode,
      itemBuilder: (context) => CardViewMode.values
          .map(
            (mode) => PopupMenuItem(
              value: mode,
              child: Row(
                children: [
                  Icon(
                    mode.icon,
                    size: 20,
                    color: mode == viewProvider.viewMode
                        ? themeProvider.getPrimaryColor()
                        : themeProvider.getSecondaryTextColor(),
                  ),
                  const SizedBox(width: 12),
                  Text(mode.label),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  /// Axis picker for the stacked grid: which attribute decides what gets stacked.
  Widget _buildStackByPills() {
    final themeProvider = context.watch<ThemeProvider>();
    final viewProvider = context.watch<CardViewProvider>();

    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 22),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final axis in CardStackBy.values)
            Padding(
              padding: const EdgeInsets.only(right: 7),
              child: _buildStackByPill(
                axis: axis,
                isSelected: viewProvider.stackBy == axis,
                themeProvider: themeProvider,
                onTap: () => viewProvider.setStackBy(axis),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStackByPill({
    required CardStackBy axis,
    required bool isSelected,
    required ThemeProvider themeProvider,
    required VoidCallback onTap,
  }) {
    final selectedColor = themeProvider.getPrimaryColor();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: isSelected
              ? selectedColor.withOpacity(0.15)
              : themeProvider.getSecondaryContainerColor(),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected ? selectedColor : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              axis.icon,
              size: 15,
              color: isSelected
                  ? selectedColor
                  : themeProvider.getSecondaryTextColor(),
            ),
            const SizedBox(width: 6),
            Text(
              axis.label,
              style: AppTypography.label(
                fontSize: 13,
                color: isSelected
                    ? selectedColor
                    : themeProvider.getSecondaryTextColor(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manage',
                  style: AppTypography.display(
                    color: themeProvider.getPrimaryTextColor(),
                  ).copyWith(height: 1.1),
                ),
                Text(
                  'Your Cards',
                  style: AppTypography.displayLight(
                    color: themeProvider.getSecondaryTextColor(),
                  ).copyWith(height: 1.1),
                ),
              ],
            ),
          ),
          _buildViewModeButton(themeProvider),
          IconButton(
            icon: Stack(
              children: [
                Icon(
                  Icons.filter_list,
                  color: themeProvider.getPrimaryTextColor(),
                  size: 28,
                ),
                if (_hasActiveFilters)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      decoration: BoxDecoration(
                        color: themeProvider.getPrimaryColor(),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          _activeFilterCount.toString(),
                          style: AppTypography.overline(color: Colors.white)
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () => _showComprehensiveFilterModal(),
          ),
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: themeProvider.getPrimaryTextColor(),
              size: 28,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final themeProvider = context.watch<ThemeProvider>();
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: themeProvider.getCardColor().withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.credit_card_off,
              size: 64,
              color: themeProvider.getSecondaryTextColor(),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No saved cards',
            style: AppTypography.pageTitle(
              color: themeProvider.getPrimaryTextColor(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to add your first card',
            style: AppTypography.subtitle(
              color: themeProvider.getSecondaryTextColor(),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildNoResultsState() {
    final themeProvider = context.watch<ThemeProvider>();
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: themeProvider.getSecondaryTextColor(),
          ),
          const SizedBox(height: 16),
          Text(
            'No cards match filters',
            style: AppTypography.appBarTitle(
              color: themeProvider.getPrimaryTextColor(),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _clearFilters,
            child: Text(
              'Clear Filters',
              style: AppTypography.subtitle(
                color: themeProvider.isDarkMode
                    ? themeProvider.getPrimaryColor()
                    : const Color(0xFF374151),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  void _showComprehensiveFilterModal() {
    final themeProvider = context.read<ThemeProvider>();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FilterModal(
        themeProvider: themeProvider,
        cards: _cards,
        allCardholderNames: _allCardholderNames,
        allBankIds: _allBankIds,
        allNicknames: _allNicknames,
        groups: _groups,
        selectedCategories: _selectedCategories,
        selectedCardholderNames: _selectedCardholderNames,
        selectedBankIds: _selectedBankIds,
        selectedNicknames: _selectedNicknames,
        selectedGroupIds: _selectedGroupIds,
        onApply: (categories, cardholders, banks, nicknames, groupIds) {
          setState(() {
            _selectedCategories = categories;
            _selectedCardholderNames = cardholders;
            _selectedBankIds = banks;
            _selectedNicknames = nicknames;
            _selectedGroupIds = groupIds;
          });
        },
      ),
    );
  }
}

class _FilterModal extends StatefulWidget {
  final ThemeProvider themeProvider;
  final List<CardData> cards;
  final Set<String> allCardholderNames;
  final Set<String> allBankIds;
  final Set<String> allNicknames;
  final List<CardGroup> groups;
  final Set<CardCategory>? selectedCategories;
  final Set<String>? selectedCardholderNames;
  final Set<String>? selectedBankIds;
  final Set<String>? selectedNicknames;
  final Set<String>? selectedGroupIds;
  final Function(
    Set<CardCategory>?,
    Set<String>?,
    Set<String>?,
    Set<String>?,
    Set<String>?,
  ) onApply;

  const _FilterModal({
    required this.themeProvider,
    required this.cards,
    required this.allCardholderNames,
    required this.allBankIds,
    required this.allNicknames,
    required this.groups,
    this.selectedCategories,
    this.selectedCardholderNames,
    this.selectedBankIds,
    this.selectedNicknames,
    this.selectedGroupIds,
    required this.onApply,
  });

  @override
  State<_FilterModal> createState() => _FilterModalState();
}

class _FilterModalState extends State<_FilterModal> {
  late Set<CardCategory> _tempCategories;
  late Set<String> _tempCardholders;
  late Set<String> _tempBanks;
  late Set<String> _tempNicknames;
  late Set<String> _tempGroups;

  @override
  void initState() {
    super.initState();
    _tempCategories = widget.selectedCategories?.toSet() ?? {};
    _tempCardholders = widget.selectedCardholderNames?.toSet() ?? {};
    _tempBanks = widget.selectedBankIds?.toSet() ?? {};
    _tempNicknames = widget.selectedNicknames?.toSet() ?? {};
    _tempGroups = widget.selectedGroupIds?.toSet() ?? {};
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: widget.themeProvider.getCardColor(),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCategorySection(),
                  const SizedBox(height: 24),
                  _buildGroupsSection(),
                  const SizedBox(height: 24),
                  _buildBanksSection(),
                  const SizedBox(height: 24),
                  _buildCardholdersSection(),
                  const SizedBox(height: 24),
                  _buildNicknamesSection(),
                ],
              ),
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final hasAnySelection = _tempCategories.isNotEmpty || 
                            _tempCardholders.isNotEmpty || 
                            _tempBanks.isNotEmpty || 
                            _tempNicknames.isNotEmpty ||
                            _tempGroups.isNotEmpty;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: widget.themeProvider.isDarkMode
                ? Colors.grey.shade800
                : Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Filter Cards',
              style: AppTypography.appBarTitle(
                color: widget.themeProvider.getPrimaryTextColor(),
              ),
            ),
          ),
          if (hasAnySelection)
            TextButton(
              onPressed: () {
                setState(() {
                  _tempCategories.clear();
                  _tempCardholders.clear();
                  _tempBanks.clear();
                  _tempNicknames.clear();
                  _tempGroups.clear();
                });
              },
              child: Text(
                'Clear All',
                style: AppTypography.body(
                  color: widget.themeProvider.getPrimaryColor(),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          IconButton(
            icon: Icon(
              Icons.close,
              color: widget.themeProvider.getPrimaryTextColor(),
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Card Type',
          style: AppTypography.title(
            color: widget.themeProvider.getPrimaryTextColor(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildCategoryChip(CardCategory.credit, 'Credit', Icons.credit_card),
            _buildCategoryChip(CardCategory.debit, 'Debit', Icons.credit_card_outlined),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryChip(CardCategory category, String label, IconData icon) {
    final isSelected = _tempCategories.contains(category);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _tempCategories.remove(category);
          } else {
            _tempCategories.add(category);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? widget.themeProvider.getPrimaryColor()
              : widget.themeProvider.getCardColor(),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? widget.themeProvider.getPrimaryColor()
                : widget.themeProvider.isDarkMode
                    ? Colors.grey.shade700
                    : const Color(0xFFD1D5DB),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : widget.themeProvider.getPrimaryTextColor(),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTypography.body(
                color: isSelected ? Colors.white : widget.themeProvider.getPrimaryTextColor(),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupsSection() {
    final usedGroupIds = widget.cards
        .map((c) => c.groupId)
        .whereType<String>()
        .toSet();
    final groups =
        widget.groups.where((g) => usedGroupIds.contains(g.id)).toList();
    if (groups.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Groups',
          style: AppTypography.title(
            color: widget.themeProvider.getPrimaryTextColor(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: groups.map((group) => _buildGroupChip(group)).toList(),
        ),
      ],
    );
  }

  Widget _buildGroupChip(CardGroup group) {
    final isSelected = _tempGroups.contains(group.id);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _tempGroups.remove(group.id);
          } else {
            _tempGroups.add(group.id);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? widget.themeProvider.getPrimaryColor()
              : widget.themeProvider.getCardColor(),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? widget.themeProvider.getPrimaryColor()
                : widget.themeProvider.isDarkMode
                    ? Colors.grey.shade700
                    : const Color(0xFFD1D5DB),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_outlined,
              size: 16,
              color: isSelected
                  ? Colors.white
                  : widget.themeProvider.getPrimaryTextColor(),
            ),
            const SizedBox(width: 6),
            Text(
              group.name,
              style: AppTypography.body(
                color: isSelected
                    ? Colors.white
                    : widget.themeProvider.getPrimaryTextColor(),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBanksSection() {
    if (widget.allBankIds.isEmpty) return const SizedBox.shrink();
    
    final banks = widget.allBankIds
        .map((id) => Banks.getById(id))
        .whereType<BankInfo>()
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Banks',
          style: AppTypography.title(
            color: widget.themeProvider.getPrimaryTextColor(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: banks.map((bank) => _buildBankChip(bank)).toList(),
        ),
      ],
    );
  }

  Widget _buildBankChip(BankInfo bank) {
    final isSelected = _tempBanks.contains(bank.id);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _tempBanks.remove(bank.id);
          } else {
            _tempBanks.add(bank.id);
          }
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? widget.themeProvider.getPrimaryColor()
                    : widget.themeProvider.isDarkMode
                        ? Colors.grey.shade700
                        : const Color(0xFFD1D5DB),
                width: isSelected ? 3 : 1.5,
              ),
            ),
            child: ClipOval(
              child: Container(
                color: widget.themeProvider.isDarkMode
                    ? Colors.grey.shade800
                    : Colors.grey.shade50,
                padding: const EdgeInsets.all(8),
                child: BankLogo(
                  bank: bank,
                  size: 32,
                  useSmall: true,
                  showFallback: true,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 56,
            child: Text(
              bank.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.overline(
                color: widget.themeProvider.getSecondaryTextColor(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardholdersSection() {
    if (widget.allCardholderNames.isEmpty) return const SizedBox.shrink();
    
    final cardholders = widget.allCardholderNames.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cardholders',
          style: AppTypography.title(
            color: widget.themeProvider.getPrimaryTextColor(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cardholders.map((name) => _buildCardholderChip(name)).toList(),
        ),
      ],
    );
  }

  Widget _buildCardholderChip(String name) {
    final isSelected = _tempCardholders.contains(name);
    final initials = _getInitials(name);
    
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _tempCardholders.remove(name);
          } else {
            _tempCardholders.add(name);
          }
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? widget.themeProvider.getPrimaryColor()
                  : widget.themeProvider.isDarkMode
                      ? Colors.grey.shade800
                      : Colors.grey.shade200,
              border: Border.all(
                color: isSelected
                    ? widget.themeProvider.getPrimaryColor()
                    : widget.themeProvider.isDarkMode
                        ? Colors.grey.shade700
                        : const Color(0xFFD1D5DB),
                width: isSelected ? 3 : 1.5,
              ),
            ),
            child: Center(
              child: Text(
                initials,
                style: AppTypography.sectionTitle(
                  color: isSelected
                      ? Colors.white
                      : widget.themeProvider.getPrimaryTextColor(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 56,
            child: Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.overline(
                color: widget.themeProvider.getSecondaryTextColor(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNicknamesSection() {
    if (widget.allNicknames.isEmpty) return const SizedBox.shrink();
    
    final nicknames = widget.allNicknames.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nicknames',
          style: AppTypography.title(
            color: widget.themeProvider.getPrimaryTextColor(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: nicknames.map((nickname) => _buildNicknameChip(nickname)).toList(),
        ),
      ],
    );
  }

  Widget _buildNicknameChip(String nickname) {
    final isSelected = _tempNicknames.contains(nickname);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _tempNicknames.remove(nickname);
          } else {
            _tempNicknames.add(nickname);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? widget.themeProvider.getPrimaryColor()
              : widget.themeProvider.getCardColor(),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? widget.themeProvider.getPrimaryColor()
                : widget.themeProvider.isDarkMode
                    ? Colors.grey.shade700
                    : const Color(0xFFD1D5DB),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.label_outline,
              size: 16,
              color: isSelected ? Colors.white : widget.themeProvider.getPrimaryTextColor(),
            ),
            const SizedBox(width: 6),
            Text(
              nickname,
              style: AppTypography.body(
                color: isSelected ? Colors.white : widget.themeProvider.getPrimaryTextColor(),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: widget.themeProvider.isDarkMode
                ? Colors.grey.shade800
                : Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: widget.themeProvider.isDarkMode
                    ? Colors.grey.shade800
                    : Colors.grey.shade200,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Cancel',
                style: AppTypography.title(
                  color: widget.themeProvider.getPrimaryTextColor(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                widget.onApply(
                  _tempCategories.isEmpty ? null : _tempCategories,
                  _tempCardholders.isEmpty ? null : _tempCardholders,
                  _tempBanks.isEmpty ? null : _tempBanks,
                  _tempNicknames.isEmpty ? null : _tempNicknames,
                  _tempGroups.isEmpty ? null : _tempGroups,
                );
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: widget.themeProvider.getPrimaryColor(),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Apply',
                style: AppTypography.title(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final words = name.trim().split(' ');
    if (words.isEmpty) return '';
    if (words.length == 1) {
      return words[0].substring(0, words[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return (words[0][0] + words[words.length - 1][0]).toUpperCase();
  }
}

class _OptionData {
  final IconData icon;
  final String label;
  final Color color;
  final AddCardOption option;

  _OptionData({
    required this.icon,
    required this.label,
    required this.color,
    required this.option,
  });
}

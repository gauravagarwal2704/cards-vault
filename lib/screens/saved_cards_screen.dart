import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/card_data.dart';
import '../models/card_group.dart';
import '../services/card_group_storage.dart';
import '../services/secure_card_storage.dart';
import '../services/ocr_service.dart';
import '../services/app_log_service.dart';
import '../providers/card_view_provider.dart';
import '../providers/nfc_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/card_tiles_grid.dart';
import '../widgets/group_picker_sheet.dart';
import '../widgets/stacked_card_grid.dart';
import '../widgets/infinite_card_deck.dart';
import '../widgets/bank_logo.dart';
import '../data/banks.dart';
import '../utils/nfc_availability_prompt.dart';
import 'card_detail_screen.dart';
import 'manual_add_card_screen.dart';
import 'card_camera_screen.dart';
import 'card_edit_screen.dart';
import 'nfc_scan_screen.dart';
import 'settings_screen.dart';
import '../theme/app_typography.dart';
import '../theme/app_motion.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_design_system.dart';

class SavedCardsScreen extends StatefulWidget {
  const SavedCardsScreen({super.key, this.cardLoader, this.groupLoader});

  final Future<List<CardData>> Function()? cardLoader;
  final Future<List<CardGroup>> Function()? groupLoader;

  @override
  State<SavedCardsScreen> createState() => _SavedCardsScreenState();
}

String _cardholderKey(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

String _cardholderLabel(String name) {
  final normalized = name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  final result = StringBuffer();
  var capitalizeNext = true;

  for (final rune in normalized.runes) {
    final character = String.fromCharCode(rune);
    final isLetter = character.toUpperCase() != character.toLowerCase();
    result.write(
      capitalizeNext && isLetter ? character.toUpperCase() : character,
    );
    if (isLetter) capitalizeNext = false;
    if (character == ' ' || character == '-' || character == "'") {
      capitalizeNext = true;
    }
  }

  return result.toString();
}

class _CustomStackGuidance extends StatefulWidget {
  const _CustomStackGuidance();

  @override
  State<_CustomStackGuidance> createState() => _CustomStackGuidanceState();
}

class _CustomStackGuidanceState extends State<_CustomStackGuidance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 6000),
    vsync: this,
  );
  bool? _reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = AppMotion.reduceMotion(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _controller
        ..stop()
        ..value = 0.84;
    } else {
      _controller
        ..value = 0
        ..repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);

    return Padding(
      key: const ValueKey('custom-stack-guidance'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: AppSurface(
        color: semantic.infoContainer,
        foregroundColor: semantic.onInfoContainer,
        shape: AppShapes.medium,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        semanticLabel:
            'Two cards are dragged one after another onto a custom stack. '
            'Animated demonstration.',
        child: Row(
          children: [
            _CustomStackDragDemo(
              animation: _controller,
              color: semantic.onInfoContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Drag a card onto another to create a stack.',
                key: const ValueKey('custom-stack-guidance-text'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label(
                  fontSize: 12,
                  color: semantic.onInfoContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomStackDragDemo extends StatelessWidget {
  final Animation<double> animation;
  final Color color;

  const _CustomStackDragDemo({required this.animation, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('custom-stack-drag-demo'),
      width: 66,
      height: 34,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final phase = animation.value;
          double progress(double start, double end) => Curves.easeInOutCubic
              .transform(((phase - start) / (end - start)).clamp(0.0, 1.0));

          final topTravel = progress(0.12, 0.36);
          final bottomTravel = progress(0.52, 0.76);
          final bottomOpacity = progress(0.48, 0.52);
          final cycleOpacity = switch (phase) {
            < 0.04 => 0.0,
            < 0.08 => progress(0.04, 0.08),
            < 0.90 => 1.0,
            < 0.96 => 1 - progress(0.90, 0.96),
            _ => 0.0,
          };

          const stackLeft = 40.0;
          const stackTop = 9.0;
          final topLeft = 2 + (stackLeft - 2) * topTravel;
          final topTop = (stackTop - 4) * topTravel;
          final bottomLeft = 2 + (stackLeft - 2) * bottomTravel;
          final bottomTop = 19 + (stackTop + 4 - 19) * bottomTravel;

          final movingTopCard = phase < 0.46;
          final handVisible =
              (phase >= 0.09 && phase <= 0.39) ||
              (phase >= 0.49 && phase <= 0.79);
          final handLeft = movingTopCard ? topLeft + 8 : bottomLeft + 8;
          final handTop = movingTopCard ? topTop + 10 : bottomTop + 10;

          return Opacity(
            key: const ValueKey('custom-stack-demo-cycle'),
            opacity: cycleOpacity,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: bottomLeft,
                  top: bottomTop,
                  child: Opacity(
                    key: const ValueKey('custom-stack-demo-bottom-card'),
                    opacity: bottomOpacity,
                    child: _DemoCard(
                      color: color.withValues(alpha: 0.18),
                      borderColor: color.withValues(alpha: 0.75),
                    ),
                  ),
                ),
                Positioned(
                  left: stackLeft,
                  top: stackTop,
                  child: _DemoCard(
                    key: const ValueKey('custom-stack-demo-target-card'),
                    color: color.withValues(alpha: 0.3),
                    borderColor: color.withValues(alpha: 0.58),
                  ),
                ),
                Positioned(
                  left: topLeft,
                  top: topTop,
                  child: _DemoCard(
                    key: const ValueKey('custom-stack-demo-top-card'),
                    color: color.withValues(alpha: 0.12),
                    borderColor: color,
                  ),
                ),
                Positioned(
                  key: const ValueKey('custom-stack-demo-hand'),
                  left: handLeft,
                  top: handTop,
                  child: Opacity(
                    opacity: handVisible ? 1 : 0,
                    child: Icon(
                      Icons.pan_tool_alt_rounded,
                      size: 14,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DemoCard extends StatelessWidget {
  final Color color;
  final Color borderColor;

  const _DemoCard({super.key, required this.color, required this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 25,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor, width: 1.2),
      ),
    );
  }
}

class _SavedCardsScreenState extends State<SavedCardsScreen>
    with TickerProviderStateMixin {
  final SecureCardStorage _cardStorage = SecureCardStorage();
  final CardGroupStorage _groupStorage = CardGroupStorage();
  List<CardData> _cards = [];
  List<CardGroup> _groups = [];
  bool _isLoading = true;
  bool _showAddOptions = false;
  bool _hasShownUnreadableDetailsWarning = false;
  int _loadGeneration = 0;
  final Set<String> _selectedCardIds = {};
  final SearchController _searchController = SearchController();
  String _searchQuery = '';

  Set<CardCategory>? _selectedCategories;
  Set<String>? _selectedCardholderNames;
  Set<String>? _selectedBankIds;
  Set<String>? _selectedNicknames;
  Set<String>? _selectedGroupIds;

  Set<String> _allCardholderNames = {};
  Map<String, String> _cardIdToCardholderName =
      {}; // Maps card ID to decrypted cardholder name

  Set<String> get _allBankIds {
    return _cards.where((c) => c.bankId != null).map((c) => c.bankId!).toSet();
  }

  Set<String> get _allNicknames {
    return _cards
        .where((c) => c.cardNickname != null && c.cardNickname!.isNotEmpty)
        .map((c) => c.cardNickname!)
        .toSet();
  }

  late AnimationController _blurController;
  late AnimationController _optionsController;
  late AnimationController _headerController;
  late Animation<double> _blurAnimation;
  late List<Animation<double>> _slideAnimations;
  late List<Animation<double>> _fadeAnimations;

  @override
  void initState() {
    super.initState();
    AppLogService.instance.action('Navigation', 'Opened wallet');
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

    _headerController = AnimationController(
      duration: AppMotion.emphasized,
      vsync: this,
    )..forward();

    _slideAnimations = List.generate(3, (index) {
      final start = index * 0.15;
      final end = start + 0.6;
      return Tween<double>(begin: 60.0, end: 0.0).animate(
        CurvedAnimation(
          parent: _optionsController,
          curve: Interval(
            start,
            end.clamp(0.0, 1.0),
            curve: Curves.easeOutBack,
          ),
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
    _headerController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduceMotion(context)) {
      _headerController.value = 1;
    }
  }

  Future<void> _loadCards() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    setState(() => _isLoading = true);

    try {
      final cards =
          await (widget.cardLoader?.call() ?? _cardStorage.loadCards());
      final groups =
          await (widget.groupLoader?.call() ?? _groupStorage.loadGroups());
      var unreadableNameCount = 0;
      final names = await Future.wait(
        cards.map((card) async {
          try {
            return await card.getDecryptedCardholderName();
          } catch (_) {
            unreadableNameCount++;
            return null;
          }
        }),
      );

      final cardIdToName = <String, String>{};
      for (int i = 0; i < cards.length; i++) {
        if (cards[i].id != null && names[i] != null) {
          cardIdToName[cards[i].id!] = names[i]!;
        }
      }

      // Navigation and settings callbacks can request another reload while an
      // older one is still decrypting names. Only the newest snapshot may
      // replace the wallet shown on screen.
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _cards = cards;
        _groups = groups;
        final namesByKey = <String, String>{};
        for (final name in names.whereType<String>()) {
          final label = _cardholderLabel(name);
          if (label.isNotEmpty) {
            namesByKey.putIfAbsent(_cardholderKey(label), () => label);
          }
        }
        _allCardholderNames = namesByKey.values.toSet();
        _cardIdToCardholderName = cardIdToName;
        _selectedCardIds.removeWhere(
          (id) => !cards.any((card) => card.id == id),
        );
        _isLoading = false;
      });
      AppLogService.instance.action(
        'Cards',
        'Wallet loaded',
        details: {
          'cardCount': cards.length,
          'groupCount': groups.length,
          'unreadableCount': unreadableNameCount,
        },
      );
      if (unreadableNameCount > 0 && !_hasShownUnreadableDetailsWarning) {
        _hasShownUnreadableDetailsWarning = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              unreadableNameCount == 1
                  ? 'One card has encrypted details that could not be read. '
                        'The card is still shown; restore a backup to recover '
                        'those details.'
                  : '$unreadableNameCount cards have encrypted details that '
                        'could not be read. The cards are still shown; restore '
                        'a backup to recover those details.',
            ),
            backgroundColor: AppSemanticColors.of(context).warning,
          ),
        );
      }
    } catch (e) {
      AppLogService.instance.record('Cards', 'Wallet load failed: $e');
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load cards: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  List<CardData> _getFilteredCards() {
    var filtered = _cards;

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((card) {
        final bankName = card.bankId == null
            ? ''
            : (Banks.getById(card.bankId!)?.name ?? card.bankId!);
        final cardholder = card.id == null
            ? ''
            : (_cardIdToCardholderName[card.id] ?? '');
        final searchable = [
          bankName,
          cardholder,
          card.cardNickname ?? '',
          card.categoryName,
          card.lastFourDigits,
        ].join(' ').toLowerCase();
        return searchable.contains(query);
      }).toList();
    }

    if (_selectedCategories != null && _selectedCategories!.isNotEmpty) {
      filtered = filtered
          .where((c) => _selectedCategories!.contains(c.cardCategory))
          .toList();
    }

    if (_selectedCardholderNames != null &&
        _selectedCardholderNames!.isNotEmpty) {
      filtered = filtered.where((card) {
        if (card.id == null) return false;
        final cardholderName = _cardIdToCardholderName[card.id];
        return cardholderName != null &&
            _selectedCardholderNames!.contains(_cardholderKey(cardholderName));
      }).toList();
    }

    if (_selectedBankIds != null && _selectedBankIds!.isNotEmpty) {
      filtered = filtered
          .where(
            (c) => c.bankId != null && _selectedBankIds!.contains(c.bankId),
          )
          .toList();
    }

    if (_selectedNicknames != null && _selectedNicknames!.isNotEmpty) {
      filtered = filtered
          .where(
            (c) =>
                c.cardNickname != null &&
                _selectedNicknames!.contains(c.cardNickname),
          )
          .toList();
    }

    if (_selectedGroupIds != null && _selectedGroupIds!.isNotEmpty) {
      filtered = filtered
          .where(
            (c) => c.groupId != null && _selectedGroupIds!.contains(c.groupId),
          )
          .toList();
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
      _searchQuery = '';
      _searchController.clear();
    });
    AppLogService.instance.action('Cards', 'Cleared wallet filters');
  }

  bool get _hasActiveFilters =>
      _searchQuery.trim().isNotEmpty ||
      (_selectedCategories != null && _selectedCategories!.isNotEmpty) ||
      (_selectedCardholderNames != null &&
          _selectedCardholderNames!.isNotEmpty) ||
      (_selectedBankIds != null && _selectedBankIds!.isNotEmpty) ||
      (_selectedNicknames != null && _selectedNicknames!.isNotEmpty) ||
      (_selectedGroupIds != null && _selectedGroupIds!.isNotEmpty);

  int get _activeFilterCount {
    int count = _searchQuery.trim().isEmpty ? 0 : 1;
    if (_selectedCategories != null) count += _selectedCategories!.length;
    if (_selectedBankIds != null) count += _selectedBankIds!.length;
    if (_selectedCardholderNames != null) {
      count += _selectedCardholderNames!.length;
    }
    if (_selectedNicknames != null) count += _selectedNicknames!.length;
    if (_selectedGroupIds != null) count += _selectedGroupIds!.length;
    return count;
  }

  String _shareTextForCard(CardData card) {
    final bank = card.bankId != null ? Banks.getById(card.bankId!) : null;
    final cardholderName = card.id != null
        ? _cardIdToCardholderName[card.id]
        : null;

    final cardInfo = StringBuffer();
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

    return cardInfo.toString().trimRight();
  }

  Future<void> _shareCards(List<CardData> cards) async {
    if (cards.isEmpty) return;

    final cardInfo = StringBuffer();
    for (var index = 0; index < cards.length; index++) {
      if (index > 0) {
        cardInfo.writeln('\n───\n');
      }
      cardInfo.writeln(
        cards.length == 1 ? 'Card Details:' : 'Card ${index + 1}:',
      );
      cardInfo.writeln();
      cardInfo.write(_shareTextForCard(cards[index]));
    }
    cardInfo.writeln('\n');
    cardInfo.writeln('⚠️ Shared from CardVault');
    cardInfo.writeln('Note: Keep your card information secure');

    try {
      await Share.share(
        cardInfo.toString(),
        subject: cards.length == 1
            ? 'Card Information'
            : '${cards.length} Card Details',
      );
      AppLogService.instance.action(
        'Card sharing',
        'Masked-card share sheet opened',
        details: {'cardCount': cards.length},
      );
    } catch (e) {
      AppLogService.instance.record('Card sharing', 'Card sharing failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _shareCard(CardData card) => _shareCards([card]);

  bool get _isSelectionMode => _selectedCardIds.isNotEmpty;

  List<CardData> get _selectedCards => _cards
      .where((card) => card.id != null && _selectedCardIds.contains(card.id))
      .toList();

  bool _bulkSelectionAllowed() {
    final viewProvider = context.read<CardViewProvider>();
    return viewProvider.viewMode != CardViewMode.stackedGrid ||
        viewProvider.stackBy != CardStackBy.custom;
  }

  void _startSelection(CardData card) {
    if (card.id == null || !_bulkSelectionAllowed()) return;
    HapticFeedback.mediumImpact();
    setState(() => _selectedCardIds.add(card.id!));
  }

  void _toggleCardSelection(CardData card) {
    if (card.id == null) return;
    setState(() {
      if (!_selectedCardIds.remove(card.id)) {
        _selectedCardIds.add(card.id!);
      }
    });
  }

  void _toggleStackSelection(List<CardData> cards) {
    final ids = cards.map((card) => card.id).whereType<String>().toSet();
    if (ids.isEmpty) return;

    setState(() {
      if (ids.every(_selectedCardIds.contains)) {
        _selectedCardIds.removeAll(ids);
      } else {
        _selectedCardIds.addAll(ids);
      }
    });
  }

  void _selectAllFilteredCards() {
    setState(() {
      _selectedCardIds.addAll(
        _getFilteredCards().map((card) => card.id).whereType<String>(),
      );
    });
  }

  void _clearSelection() {
    if (_selectedCardIds.isEmpty) return;
    setState(_selectedCardIds.clear);
  }

  Future<void> _shareSelectedCards() async {
    final cards = _selectedCards;
    if (cards.isEmpty) return;
    await _shareCards(cards);
    if (mounted) _clearSelection();
  }

  Future<void> _deleteSelectedCards() async {
    final cards = _selectedCards;
    if (cards.isEmpty) return;

    final count = cards.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $count card${count == 1 ? '' : 's'}?'),
        content: const Text(
          'The selected cards and their photos will be permanently deleted. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      for (final card in cards) {
        if (card.id != null) await _cardStorage.deleteCard(card.id!);
      }
      AppLogService.instance.action(
        'Cards',
        'Bulk card deletion completed',
        details: {'count': count},
      );
      _clearSelection();
      await _loadCards();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count card${count == 1 ? '' : 's'} deleted'),
          backgroundColor: AppSemanticColors.of(context).success,
        ),
      );
    } catch (e) {
      AppLogService.instance.record('Cards', 'Bulk card deletion failed: $e');
      await _loadCards();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete selected cards: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
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
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && card.id != null) {
      try {
        await _cardStorage.deleteCard(card.id!);
        AppLogService.instance.action('Cards', 'Card deleted');
        await _loadCards();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Card deleted'),
              backgroundColor: AppSemanticColors.of(context).success,
            ),
          );
        }
      } catch (e) {
        AppLogService.instance.record('Cards', 'Card deletion failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  void _onCardTap(CardData card) async {
    if (_isSelectionMode) {
      _toggleCardSelection(card);
      return;
    }

    AppLogService.instance.action('Navigation', 'Opened card details');

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CardDetailScreen(card: card, cardIndex: _cards.indexOf(card)),
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
    AppLogService.instance.action(
      'Cards',
      'Card group changed',
      details: {'grouped': selection.group != null},
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
        backgroundColor: AppSemanticColors.of(context).success,
      ),
    );
  }

  void _toggleAddOptions() {
    setState(() {
      _showAddOptions = !_showAddOptions;
    });
    if (AppMotion.reduceMotion(context)) {
      _blurController.value = _showAddOptions ? 1 : 0;
      _optionsController.value = _showAddOptions ? 1 : 0;
    } else if (_showAddOptions) {
      _blurController.forward();
      _optionsController.forward();
    } else {
      _optionsController.reverse();
      _blurController.reverse();
    }
  }

  void _handleAddOption(_AddCardOption option) async {
    AppLogService.instance.action(
      'Cards',
      'Add-card method selected',
      details: {'method': option.name},
    );
    _toggleAddOptions();

    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;

    switch (option) {
      case _AddCardOption.nfc:
        final nfcReady = await ensureNfcReady(context);
        if (!mounted || !nfcReady) break;
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (context) => const NfcScanScreen()),
        );
        if (result == true && mounted) _loadCards();
        break;
      case _AddCardOption.scan:
        await _handleCameraScan();
        break;
      case _AddCardOption.manual:
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ManualAddCardScreen()),
        );
        if (mounted) _loadCards();
        break;
    }
  }

  Future<void> _handleCameraScan() async {
    final ocrResult = await Navigator.push<OCRResult>(
      context,
      MaterialPageRoute(builder: (context) => const CardCameraScreen()),
    );

    if (ocrResult == null || !mounted) return;

    final cardData = await Navigator.push<CardData>(
      context,
      MaterialPageRoute(
        builder: (context) => CardEditScreen(ocrResult: ocrResult),
      ),
    );

    if (cardData != null && mounted) {
      await _cardStorage.saveCard(cardData);
      AppLogService.instance.action('Cards', 'Scanned card saved');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Card saved successfully!'),
          backgroundColor: AppSemanticColors.of(context).success,
        ),
      );
      _loadCards();
    }
  }

  Widget _buildCardsView() {
    final cards = _getFilteredCards();
    final viewProvider = context.watch<CardViewProvider>();

    switch (viewProvider.viewMode) {
      case CardViewMode.carousel:
        return InfiniteCardDeck(
          cards: cards,
          onCardTap: _onCardTap,
          onCardLongPress: _startSelection,
          onCardShare: _shareCard,
          onCardDelete: _deleteCard,
          selectedCardIds: _selectedCardIds,
          selectionMode: _isSelectionMode,
        );
      case CardViewMode.stackedGrid:
        final stackBy = viewProvider.stackBy;
        if (stackBy == CardStackBy.none) {
          return CardTilesGrid(
            cards: cards,
            onCardTap: _onCardTap,
            onCardLongPress: _startSelection,
            selectedCardIds: _selectedCardIds,
            selectionMode: _isSelectionMode,
          );
        }
        final isCustom = stackBy == CardStackBy.custom;
        return StackedCardGrid(
          stacks: _buildStacks(cards, stackBy),
          axisKey: stackBy.name,
          canGroupByDrag: isCustom,
          onCardTap: _onCardTap,
          onCardLongPress: isCustom ? _changeCardGroup : _startSelection,
          selectedCardIds: _selectedCardIds,
          selectionMode: !isCustom && _isSelectionMode,
          onStackSelectionToggle: isCustom ? null : _toggleStackSelection,
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
    final name = await showGroupNameSheet(
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
        backgroundColor: AppSemanticColors.of(context).success,
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
        CardStackBy.none => (
          key: card.id ?? 'card-${card.lastFourDigits}',
          title: card.cardNickname?.isNotEmpty == true
              ? card.cardNickname!
              : card.categoryName,
        ),
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
        .map(
          (entry) => CardStack(
            key: entry.key,
            title: titles[entry.key]!,
            cards: entry.value,
            bankId: bankIds[entry.key],
            groupId: axis == CardStackBy.custom && entry.key != unassignedKey
                ? entry.key
                : null,
            icon: icons[entry.key],
          ),
        )
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
        result.add(
          CardStack(
            key: card.id ?? 'card-${card.lastFourDigits}',
            title: nickname != null && nickname.isNotEmpty
                ? nickname
                : card.categoryName,
            cards: [card],
          ),
        );
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
    final label = _cardholderLabel(name);
    return (key: _cardholderKey(name), title: label);
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
    final viewMode = context.watch<CardViewProvider>().viewMode;
    final filteredCards = _getFilteredCards();
    final reserveBottomSpace =
        viewMode == CardViewMode.carousel ||
        _cards.isEmpty ||
        filteredCards.isEmpty;

    return Scaffold(
      backgroundColor: themeProvider.getBackgroundColor(),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(context),
                if (!_isSelectionMode && _cards.isNotEmpty)
                  _buildCollectionControls(),
                if (viewMode == CardViewMode.stackedGrid &&
                    !_isSelectionMode &&
                    _cards.isNotEmpty)
                  _buildStackByPills(),
                if (viewMode == CardViewMode.stackedGrid &&
                    context.watch<CardViewProvider>().stackBy ==
                        CardStackBy.custom &&
                    !_isSelectionMode &&
                    _cards.isNotEmpty)
                  _buildCustomStackGuidance(),
                Expanded(
                  key: const ValueKey('wallet-cards-view'),
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _cards.isEmpty
                      ? _buildEmptyState()
                      : filteredCards.isEmpty
                      ? _buildNoResultsState()
                      : _buildCardsView(),
                ),
                if (reserveBottomSpace) const SizedBox(height: 100),
              ],
            ),
            if (_showAddOptions) _buildBlurOverlay(),
            if (!_isSelectionMode)
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
        return Semantics(
          button: true,
          label: 'Close add card menu',
          child: GestureDetector(
            onTap: _toggleAddOptions,
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: 8 * _blurAnimation.value,
                sigmaY: 8 * _blurAnimation.value,
              ),
              child: Container(
                color: Colors.black.withValues(
                  alpha: 0.3 * _blurAnimation.value,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomSection() {
    final themeProvider = context.watch<ThemeProvider>();
    final scheme = Theme.of(context).colorScheme;
    final buttonColor = _showAddOptions
        ? scheme.tertiaryContainer
        : scheme.primaryContainer;
    final buttonForeground = _showAddOptions
        ? scheme.onTertiaryContainer
        : scheme.onPrimaryContainer;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showAddOptions) _buildPillOptions(),
          PressableScale(
            child: AnimatedContainer(
              duration: AppMotion.resolve(context, AppMotion.standard),
              curve: AppMotion.standardCurve,
              width: _showAddOptions ? 112 : 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.2),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: AppSurface(
                padding: EdgeInsets.zero,
                color: buttonColor,
                foregroundColor: buttonForeground,
                shape: AppShapes.pill,
                onTap: _toggleAddOptions,
                semanticLabel: _showAddOptions
                    ? 'Close add card menu'
                    : 'Add card',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedRotation(
                      turns: _showAddOptions ? 0.125 : 0,
                      duration: AppMotion.resolve(context, AppMotion.standard),
                      curve: AppMotion.standardCurve,
                      child: Icon(Icons.add, color: buttonForeground, size: 22),
                    ),
                    AnimatedSize(
                      duration: AppMotion.resolve(context, AppMotion.standard),
                      curve: AppMotion.standardCurve,
                      child: _showAddOptions
                          ? Padding(
                              padding: const EdgeInsets.only(left: 7),
                              child: Text(
                                'Add…',
                                style: AppTypography.label(
                                  color: buttonForeground,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
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
        option: _AddCardOption.manual,
      ),
      _OptionData(
        icon: Icons.camera_alt_outlined,
        label: 'Scan Card',
        color: AppSemanticColors.of(context).success,
        option: _AddCardOption.scan,
      ),
      _OptionData(
        icon: Icons.contactless_outlined,
        label: 'Add via NFC',
        color: AppSemanticColors.of(context).info,
        option: _AddCardOption.nfc,
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
            final slideAnim =
                _slideAnimations[animIndex % _slideAnimations.length];
            final fadeAnim =
                _fadeAnimations[animIndex % _fadeAnimations.length];

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
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      child: AppSurface(
        onTap: onTap,
        semanticLabel: label,
        shape: AppShapes.pill,
        color: scheme.surfaceContainerHigh,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: AppSpacing.xs),
            Text(label, style: AppTypography.label(color: scheme.onSurface)),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionControls() {
    final viewProvider = context.watch<CardViewProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<CardViewMode>(
              expandedInsets: EdgeInsets.zero,
              showSelectedIcon: false,
              segments: [
                for (final mode in CardViewMode.values)
                  ButtonSegment(
                    value: mode,
                    icon: Icon(mode.icon, size: 18),
                    label: Text(mode.label),
                  ),
              ],
              selected: {viewProvider.viewMode},
              onSelectionChanged: (selection) {
                viewProvider.setViewMode(selection.single);
              },
            ),
          ),
          if (_hasActiveFilters) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (_searchQuery.trim().isNotEmpty)
                  InputChip(
                    avatar: const Icon(Icons.search_rounded, size: 17),
                    label: Text('“${_searchQuery.trim()}”'),
                    onDeleted: () => setState(() {
                      _searchQuery = '';
                      _searchController.clear();
                    }),
                  ),
                if (_activeFilterCount - (_searchQuery.trim().isEmpty ? 0 : 1) >
                    0)
                  InputChip(
                    avatar: const Icon(Icons.filter_alt_rounded, size: 17),
                    label: Text(
                      '${_activeFilterCount - (_searchQuery.trim().isEmpty ? 0 : 1)} filters',
                    ),
                    onDeleted: _clearFilters,
                  ),
                ActionChip(
                  avatar: const Icon(Icons.close_rounded, size: 17),
                  label: const Text('Clear'),
                  onPressed: _clearFilters,
                  backgroundColor: scheme.surfaceContainerHigh,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Axis picker for the stacked grid: which attribute decides what gets stacked.
  Widget _buildStackByPills() {
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
                onTap: () => viewProvider.setStackBy(axis),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomStackGuidance() {
    return const _CustomStackGuidance();
  }

  Widget _buildStackByPill({
    required CardStackBy axis,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      selected: isSelected,
      avatar: Icon(axis.icon, size: 16),
      label: Text(axis.label),
      onSelected: (_) => onTap(),
    );
  }

  Widget _buildHeader(BuildContext context) {
    if (_isSelectionMode) return _buildSelectionHeader();

    final themeProvider = context.watch<ThemeProvider>();
    final displayName = context.watch<ProfileProvider>().displayName;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
      child: Row(
        children: [
          Expanded(
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _headerController,
                curve: Curves.easeOut,
              ),
              child: SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(-0.08, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: _headerController,
                        curve: AppMotion.standardCurve,
                      ),
                    ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CardVault',
                      style: AppTypography.display(
                        color: themeProvider.getPrimaryTextColor(),
                      ).copyWith(height: 1.1),
                    ),
                    AnimatedSwitcher(
                      duration: AppMotion.standard,
                      child: Text(
                        'Welcome back, $displayName',
                        key: ValueKey(displayName),
                        style: AppTypography.subtitle(
                          color: themeProvider.getSecondaryTextColor(),
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildSearchAction(),
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
            onPressed: () async {
              AppLogService.instance.action('Navigation', 'Opened Settings');
              // Only import/delete operations call back into the wallet. Smart
              // Scan, appearance, and security settings therefore cannot
              // replace the full in-memory list with a transient partial read
              // from secure storage when the route closes.
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      SettingsScreen(onCardsChanged: _loadCards),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAction() {
    final scheme = Theme.of(context).colorScheme;
    return SearchAnchor(
      searchController: _searchController,
      viewHintText: 'Search cards, banks, or people',
      viewOnChanged: (value) => setState(() => _searchQuery = value),
      viewOnSubmitted: (value) {
        setState(() => _searchQuery = value);
        _searchController.closeView(value);
      },
      viewTrailing: [
        if (_searchController.text.isNotEmpty)
          IconButton(
            tooltip: 'Clear search',
            onPressed: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            },
            icon: const Icon(Icons.close_rounded),
          ),
      ],
      suggestionsBuilder: (context, controller) {
        final query = controller.text.trim().toLowerCase();
        if (query.isEmpty) {
          return [
            ListTile(
              leading: const Icon(Icons.search_rounded),
              title: const Text('Search your cards'),
              subtitle: const Text(
                'Try a bank, nickname, person, or last four',
              ),
              enabled: false,
            ),
          ];
        }

        final matches = _cards
            .where((card) {
              final bank = card.bankId == null
                  ? ''
                  : (Banks.getById(card.bankId!)?.name ?? card.bankId!);
              final holder = card.id == null
                  ? ''
                  : (_cardIdToCardholderName[card.id] ?? '');
              return [
                bank,
                holder,
                card.cardNickname ?? '',
                card.categoryName,
                card.lastFourDigits,
              ].join(' ').toLowerCase().contains(query);
            })
            .take(8);

        if (matches.isEmpty) {
          return [
            const ListTile(
              leading: Icon(Icons.search_off_rounded),
              title: Text('No matching cards'),
              enabled: false,
            ),
          ];
        }

        return matches.map((card) {
          final bank = card.bankId == null ? null : Banks.getById(card.bankId!);
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.secondaryContainer,
              foregroundColor: scheme.onSecondaryContainer,
              child: const Icon(Icons.credit_card_rounded),
            ),
            title: Text(card.cardNickname ?? bank?.name ?? card.categoryName),
            subtitle: Text('${card.categoryName} •••• ${card.lastFourDigits}'),
            onTap: () {
              controller.closeView(query);
              setState(() => _searchQuery = query);
              _onCardTap(card);
            },
          );
        });
      },
      builder: (context, controller) => IconButton(
        tooltip: 'Search cards',
        onPressed: controller.openView,
        icon: Icon(
          _searchQuery.isEmpty
              ? Icons.search_rounded
              : Icons.search_off_rounded,
          color: scheme.onSurface,
          size: 27,
        ),
      ),
    );
  }

  Widget _buildSelectionHeader() {
    final themeProvider = context.watch<ThemeProvider>();
    final scheme = Theme.of(context).colorScheme;
    final filteredIds = _getFilteredCards()
        .map((card) => card.id)
        .whereType<String>()
        .toSet();
    final allFilteredSelected =
        filteredIds.isNotEmpty && filteredIds.every(_selectedCardIds.contains);

    return AnimatedContainer(
      duration: AppMotion.resolve(context, AppMotion.standard),
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 18),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: ShapeDecoration(
        color: scheme.surfaceContainerHigh,
        shape: AppShapes.large,
        shadows: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('bulk-selection-close'),
            tooltip: 'Close selection',
            onPressed: _clearSelection,
            icon: Icon(Icons.close, color: themeProvider.getPrimaryTextColor()),
          ),
          Expanded(
            child: Text(
              '${_selectedCardIds.length} selected',
              key: const ValueKey('bulk-selection-count'),
              style: AppTypography.appBarTitle(
                color: themeProvider.getPrimaryTextColor(),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('bulk-select-all'),
            tooltip: allFilteredSelected ? 'All selected' : 'Select all',
            onPressed: allFilteredSelected ? null : _selectAllFilteredCards,
            icon: Icon(
              Icons.select_all,
              color: allFilteredSelected
                  ? themeProvider.getSecondaryTextColor()
                  : themeProvider.getPrimaryTextColor(),
            ),
          ),
          IconButton(
            key: const ValueKey('bulk-share'),
            tooltip: 'Share selected',
            onPressed: _shareSelectedCards,
            icon: Icon(
              Icons.share_outlined,
              color: themeProvider.getPrimaryTextColor(),
            ),
          ),
          IconButton(
            key: const ValueKey('bulk-delete'),
            tooltip: 'Delete selected',
            onPressed: _deleteSelectedCards,
            icon: Icon(Icons.delete_outline, color: scheme.error),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final themeProvider = context.watch<ThemeProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
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
    final scheme = Theme.of(context).colorScheme;

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
              'Clear filters',
              style: AppTypography.subtitle(color: scheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  void _showComprehensiveFilterModal() {
    final themeProvider = context.read<ThemeProvider>();
    Widget buildFilter() => _FilterModal(
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
    );

    if (MediaQuery.sizeOf(context).width >= 900) {
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Close filters',
        barrierColor: Theme.of(context).colorScheme.scrim
            .withValues(alpha: 0.32),
        transitionDuration: AppMotion.resolve(context, AppMotion.standard),
        pageBuilder: (context, animation, secondaryAnimation) => Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 480,
            height: double.infinity,
            child: buildFilter(),
          ),
        ),
        transitionBuilder: (context, animation, secondaryAnimation, child) =>
            SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: AppMotion.standardCurve,
                    ),
                  ),
              child: child,
            ),
      );
    } else {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => buildFilter(),
      );
    }
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
  )
  onApply;

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
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Container(
      height: wide ? double.infinity : MediaQuery.sizeOf(context).height * 0.85,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: wide
            ? const BorderRadius.horizontal(left: Radius.circular(32))
            : const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.xl,
              ),
              child: SizedBox(
                key: const ValueKey('filter-sheet-content'),
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCategorySection(),
                    const SizedBox(height: AppSpacing.xl),
                    _buildGroupsSection(),
                    const SizedBox(height: AppSpacing.xl),
                    _buildBanksSection(),
                    const SizedBox(height: AppSpacing.xl),
                    _buildCardholdersSection(),
                    const SizedBox(height: AppSpacing.xl),
                    _buildNicknamesSection(),
                  ],
                ),
              ),
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final scheme = Theme.of(context).colorScheme;
    final hasAnySelection =
        _tempCategories.isNotEmpty ||
        _tempCardholders.isNotEmpty ||
        _tempBanks.isNotEmpty ||
        _tempNicknames.isNotEmpty ||
        _tempGroups.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Filter Cards',
              key: const ValueKey('filter-sheet-title'),
              style: AppTypography.appBarTitle(color: scheme.onSurface),
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
              child: const Text('Clear all'),
            ),
          IconButton(
            icon: const Icon(Icons.close),
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
            _buildCategoryChip(
              CardCategory.credit,
              'Credit',
              Icons.credit_card,
            ),
            _buildCategoryChip(
              CardCategory.debit,
              'Debit',
              Icons.credit_card_outlined,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryChip(
    CardCategory category,
    String label,
    IconData icon,
  ) {
    final isSelected = _tempCategories.contains(category);
    return FilterChip(
      selected: isSelected,
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onSelected: (_) {
        setState(() {
          if (isSelected) {
            _tempCategories.remove(category);
          } else {
            _tempCategories.add(category);
          }
        });
      },
    );
  }

  Widget _buildGroupsSection() {
    final usedGroupIds = widget.cards
        .map((c) => c.groupId)
        .whereType<String>()
        .toSet();
    final groups = widget.groups
        .where((g) => usedGroupIds.contains(g.id))
        .toList();
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
    return FilterChip(
      selected: isSelected,
      avatar: const Icon(Icons.folder_outlined, size: 18),
      label: Text(group.name),
      onSelected: (_) {
        setState(() {
          if (isSelected) {
            _tempGroups.remove(group.id);
          } else {
            _tempGroups.add(group.id);
          }
        });
      },
    );
  }

  Widget _buildBanksSection() {
    if (widget.allBankIds.isEmpty) return const SizedBox.shrink();

    final banks =
        widget.allBankIds
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
    return FilterChip(
      selected: isSelected,
      avatar: BankLogo(
        bank: bank,
        size: 22,
        useSmall: true,
        showFallback: true,
      ),
      label: Text(bank.shortName),
      onSelected: (_) {
        setState(() {
          if (isSelected) {
            _tempBanks.remove(bank.id);
          } else {
            _tempBanks.add(bank.id);
          }
        });
      },
    );
  }

  Widget _buildCardholdersSection() {
    if (widget.allCardholderNames.isEmpty) return const SizedBox.shrink();

    final cardholders = widget.allCardholderNames.toList()
      ..sort((a, b) => _cardholderKey(a).compareTo(_cardholderKey(b)));

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
          children: cardholders
              .map((name) => _buildCardholderChip(name))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildCardholderChip(String name) {
    final key = _cardholderKey(name);
    final isSelected = _tempCardholders.contains(key);
    final initials = _getInitials(name);
    final scheme = Theme.of(context).colorScheme;

    return FilterChip(
      selected: isSelected,
      avatar: SizedBox.square(
        key: ValueKey('cardholder-avatar-$key'),
        dimension: 20,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected
                ? scheme.onSecondaryContainer.withValues(alpha: 0.12)
                : scheme.secondaryContainer,
          ),
          child: Padding(
            key: ValueKey('cardholder-avatar-padding-$key'),
            padding: const EdgeInsets.all(3),
            child: Center(
              child: Text(
                initials,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  height: 1,
                  fontSize: 10,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
        ),
      ),
      label: Text(name),
      onSelected: (_) {
        setState(() {
          if (isSelected) {
            _tempCardholders.remove(key);
          } else {
            _tempCardholders.add(key);
          }
        });
      },
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
          children: nicknames
              .map((nickname) => _buildNicknameChip(nickname))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildNicknameChip(String nickname) {
    final isSelected = _tempNicknames.contains(nickname);
    return FilterChip(
      selected: isSelected,
      avatar: const Icon(Icons.label_outline, size: 18),
      label: Text(nickname),
      onSelected: (_) {
        setState(() {
          if (isSelected) {
            _tempNicknames.remove(nickname);
          } else {
            _tempNicknames.add(nickname);
          }
        });
      },
    );
  }

  Widget _buildFooter() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
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
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Apply filters'),
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) return '';
    if (words.length == 1) {
      return words[0].substring(0, words[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return (words[0][0] + words[words.length - 1][0]).toUpperCase();
  }
}

enum _AddCardOption { nfc, scan, manual }

class _OptionData {
  final IconData icon;
  final String label;
  final Color color;
  final _AddCardOption option;

  _OptionData({
    required this.icon,
    required this.label,
    required this.color,
    required this.option,
  });
}

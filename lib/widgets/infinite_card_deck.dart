import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../models/card_data.dart';
import '../data/banks.dart';
import '../data/card_designs.dart';
import 'wallet_card.dart';
import 'bank_logo.dart';
import 'card_network_logo.dart';
import 'swipeable_card.dart';
import '../theme/app_typography.dart';
import '../theme/app_motion.dart';
import '../utils/card_network_utils.dart';
import '../utils/card_contrast.dart';
import 'card_background_surface.dart';
import 'wallet_card_hero.dart';

class InfiniteCardDeck extends StatefulWidget {
  final List<CardData> cards;
  final Function(CardData card)? onCardTap;
  final Function(CardData card)? onCardLongPress;
  final Function(int index)? onCardChanged;
  final Function(CardData card)? onCardShare;
  final Function(CardData card)? onCardDelete;
  final Set<String> selectedCardIds;
  final bool selectionMode;
  final int initialIndex;

  const InfiniteCardDeck({
    super.key,
    required this.cards,
    this.onCardTap,
    this.onCardLongPress,
    this.onCardChanged,
    this.onCardShare,
    this.onCardDelete,
    this.selectedCardIds = const {},
    this.selectionMode = false,
    this.initialIndex = 0,
  });

  @override
  State<InfiniteCardDeck> createState() => _InfiniteCardDeckState();
}

class _DecryptedCardData {
  final String? cardholderName;
  final String? expiryDate;

  _DecryptedCardData({this.cardholderName, this.expiryDate});
}

class _InfiniteCardDeckState extends State<InfiniteCardDeck>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  double _currentIndex = 0;
  double _targetIndex = 0;
  double _dragPixelsPerCard = 120;
  int _lastHapticIndex = 0;

  // Credit card aspect ratio: 85.6mm x 53.98mm = 1.586:1
  static const double _cardAspectRatio = 1.586;
  static const double _cardWidthPercent = 0.85;
  static const int _maxVisibleCards = 7;
  static const double _peekPercent = 0.22;
  static const double _depthCompression = 0.76;

  int _lastReportedIndex = 0;

  final Map<String, _DecryptedCardData> _cardDataCache = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.toDouble();
    _targetIndex = _currentIndex;
    _lastReportedIndex = widget.initialIndex;
    _lastHapticIndex = widget.initialIndex;
    _animationController = AnimationController.unbounded(
      vsync: this,
      value: _currentIndex,
    );
    _animationController.addListener(_onAnimationUpdate);
    _animationController.addStatusListener(_onAnimationStatus);
    _preloadCardData();
  }

  @override
  void didUpdateWidget(covariant InfiniteCardDeck oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.cards.length != widget.cards.length) {
      _animationController.stop();
      if (widget.cards.isEmpty) {
        _targetIndex = 0;
        _animationController.value = 0;
      } else {
        final normalized = _getRealIndex(_currentIndex.round()).toDouble();
        _targetIndex = normalized;
        _animationController.value = normalized;
      }
    }

    final activeIds = widget.cards
        .map((card) => card.id)
        .whereType<String>()
        .toSet();
    _cardDataCache.removeWhere((id, _) => !activeIds.contains(id));
    _preloadCardData();
  }

  Future<void> _preloadCardData() async {
    final missingCards = widget.cards
        .where(
          (card) => card.id != null && !_cardDataCache.containsKey(card.id),
        )
        .toList();
    if (missingCards.isEmpty) return;

    final entries = await Future.wait(
      missingCards.map((card) async {
        try {
          return MapEntry(
            card.id!,
            _DecryptedCardData(
              cardholderName: await card.getDecryptedCardholderName(),
              expiryDate: await card.getDecryptedExpiryDate(),
            ),
          );
        } catch (_) {
          return null;
        }
      }),
    );

    if (!mounted) return;
    setState(() {
      for (final entry
          in entries.whereType<MapEntry<String, _DecryptedCardData>>()) {
        _cardDataCache[entry.key] = entry.value;
      }
    });
  }

  @override
  void dispose() {
    _animationController.removeListener(_onAnimationUpdate);
    _animationController.removeStatusListener(_onAnimationStatus);
    _animationController.dispose();
    super.dispose();
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _completeTransition();
  }

  void _onAnimationUpdate() {
    if (!mounted) return;
    setState(() => _currentIndex = _animationController.value);
  }

  void _animateToIndex(double target, {double velocity = 0}) {
    _targetIndex = target;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (reduceMotion) {
      _animationController.stop();
      _animationController.value = target;
      _completeTransition();
      return;
    }

    _animationController.animateWith(
      SpringSimulation(
        AppMotion.carouselSpring,
        _currentIndex,
        target,
        velocity.clamp(-8.0, 8.0).toDouble(),
      ),
    );
  }

  void _completeTransition() {
    if (widget.cards.isEmpty) return;

    final currentIdx = _getRealIndex(_targetIndex.round());
    _targetIndex = currentIdx.toDouble();
    if ((_animationController.value - _targetIndex).abs() > 0.001) {
      _animationController.value = _targetIndex;
    }

    HapticFeedback.lightImpact();
    if (currentIdx != _lastReportedIndex) {
      _lastReportedIndex = currentIdx;
      widget.onCardChanged?.call(currentIdx);
    }
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _animationController.stop();
    _lastHapticIndex = _currentIndex.round();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    final newIndex = _currentIndex - (delta / _dragPixelsPerCard);
    final newRoundedIndex = newIndex.round();

    if (newRoundedIndex != _lastHapticIndex) {
      _lastHapticIndex = newRoundedIndex;
      HapticFeedback.selectionClick();
    }

    _animationController.value = newIndex;
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final indexVelocity = -(details.primaryVelocity ?? 0) / _dragPixelsPerCard;
    final projectedMove = (indexVelocity * 0.16).clamp(-3.0, 3.0);
    final target = (_currentIndex + projectedMove).roundToDouble();

    _animateToIndex(target, velocity: indexVelocity);
  }

  void _onCardTapped(int virtualIndex) {
    _animateToIndex(virtualIndex.toDouble());
  }

  int _getRealIndex(int virtualIndex) {
    if (widget.cards.isEmpty) return 0;
    return ((virtualIndex % widget.cards.length) + widget.cards.length) %
        widget.cards.length;
  }

  double _packedDistance(double depth) {
    return (1 - math.pow(_depthCompression, depth)) / (1 - _depthCompression);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) {
      return const SizedBox.shrink();
    }

    return ClipRect(
      child: GestureDetector(
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        behavior: HitTestBehavior.opaque,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth * _cardWidthPercent;
            final cardHeight = cardWidth / _cardAspectRatio;
            final indicatorSpace = widget.cards.length > 1 ? 54.0 : 0.0;
            final stackHeight = math.max(
              cardHeight,
              constraints.maxHeight - indicatorSpace,
            );
            final centerY = (stackHeight - cardHeight) / 2;
            final horizontalPadding = (constraints.maxWidth - cardWidth) / 2;
            final visibleCardCount = math.min(
              widget.cards.length,
              _maxVisibleCards,
            );
            final cardsAbove = (visibleCardCount - 1) ~/ 2;
            final cardsBelow = visibleCardCount - 1 - cardsAbove;
            final maxDepth = math.max(cardsAbove, cardsBelow);
            final packedDepth = _packedDistance(maxDepth.toDouble());
            final availablePerSide = math.max(
              0.0,
              (stackHeight - cardHeight) / 2,
            );
            final adaptivePeek = maxDepth == 0
                ? cardHeight * _peekPercent
                : availablePerSide / packedDepth;
            final peekAmount = math.min(
              cardHeight * _peekPercent,
              math.max(12.0, adaptivePeek),
            );
            _dragPixelsPerCard = math.max(72.0, peekAmount * 2.8);

            final cardsToRender = <_CardRenderData>[];

            // Render only the nearby depth window. Offscreen cards do not need
            // to be painted while the user manipulates the deck.
            for (int offset = -cardsAbove; offset <= cardsBelow; offset++) {
              final virtualIndex = _currentIndex.round() + offset;
              final realIndex = _getRealIndex(virtualIndex);

              // Calculate continuous difference from current scroll position
              final diff = virtualIndex - _currentIndex;

              cardsToRender.add(
                _calculateCardData(
                  virtualIndex: virtualIndex,
                  realIndex: realIndex,
                  diff: diff,
                  centerY: centerY,
                  cardHeight: cardHeight,
                  cardWidth: cardWidth,
                  horizontalPadding: horizontalPadding,
                  peekAmount: peekAmount,
                ),
              );
            }

            // Sort by z-order: cards furthest from center render first (behind)
            cardsToRender.sort((a, b) => b.diff.abs().compareTo(a.diff.abs()));

            final currentRealIndex = _getRealIndex(_currentIndex.round());
            final lowestCardBottom = cardsToRender
                .map(
                  (data) =>
                      data.yPosition +
                      (data.cardHeight + data.cardHeight * data.scale) / 2,
                )
                .reduce(math.max);
            final indicatorTop = (lowestCardBottom + 16)
                .clamp(0.0, math.max(0.0, constraints.maxHeight - 32))
                .toDouble();

            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                ...cardsToRender.map((data) => _buildCardWidget(data)),
                if (widget.cards.length > 1)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: indicatorTop,
                    child: IgnorePointer(
                      child: Center(
                        child: _buildPositionIndicator(
                          context,
                          currentRealIndex,
                          widget.cards.length,
                        ),
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

  _CardRenderData _calculateCardData({
    required int virtualIndex,
    required int realIndex,
    required double diff,
    required double centerY,
    required double cardHeight,
    required double cardWidth,
    required double horizontalPadding,
    required double peekAmount,
  }) {
    final absDiff = diff.abs();
    final isFocused = absDiff < 0.5;

    // Continuous interpolation for smooth animation
    double scale;
    double yOffset;
    double opacity;

    if (absDiff < 0.01) {
      // Exactly focused
      scale = 1.0;
      yOffset = 0;
      opacity = 1.0;
    } else {
      // Scale decreases smoothly as card moves away from center
      scale = (1.0 - absDiff * 0.045).clamp(0.86, 1.0);

      // Compress cards farther from the focus so a large wallet still reads
      // as one tidy deck instead of a tall, clipped column.
      final packedDistance = _packedDistance(absDiff);
      yOffset = diff.sign * peekAmount * packedDistance;

      opacity = (1.0 - absDiff * 0.16).clamp(0.52, 1.0);
    }

    return _CardRenderData(
      realIndex: realIndex,
      virtualIndex: virtualIndex,
      diff: diff,
      scale: scale,
      yPosition: centerY + yOffset,
      cardHeight: cardHeight,
      cardWidth: cardWidth,
      horizontalPadding: horizontalPadding,
      opacity: opacity,
      isFocused: isFocused,
    );
  }

  Widget _buildCardWidget(_CardRenderData data) {
    final card = widget.cards[data.realIndex];

    final scaledWidth = data.cardWidth * data.scale;
    final scaledHeight = data.cardHeight * data.scale;
    final leftOffset =
        data.horizontalPadding + (data.cardWidth - scaledWidth) / 2;

    Widget cardWidget = Semantics(
      button: true,
      selected: data.isFocused,
      label:
          '${card.categoryName} card ending ${card.lastFourDigits}. ${data.realIndex + 1} of ${widget.cards.length}',
      child: GestureDetector(
        onTap: () {
          if (data.isFocused) {
            widget.onCardTap?.call(widget.cards[data.realIndex]);
          } else {
            _onCardTapped(data.virtualIndex);
          }
        },
        onLongPress: data.isFocused
            ? () => widget.onCardLongPress?.call(widget.cards[data.realIndex])
            : null,
        child: Opacity(
          opacity: data.opacity.clamp(0.0, 1.0),
          child: _buildCard(card, data.isFocused),
        ),
      ),
    );

    // Wrap focused card with SwipeableCard
    if (data.isFocused && !widget.selectionMode) {
      cardWidget = SwipeableCard(
        key: ValueKey('deck-swipe-${card.id ?? data.realIndex}'),
        cardWidth: scaledWidth,
        cardHeight: scaledHeight,
        onShare: () => widget.onCardShare?.call(widget.cards[data.realIndex]),
        onDelete: () => widget.onCardDelete?.call(widget.cards[data.realIndex]),
        child: cardWidget,
      );
    }

    return Positioned(
      key: ValueKey('deck-card-${card.id ?? data.realIndex}'),
      left: leftOffset,
      top: data.yPosition + (data.cardHeight - scaledHeight) / 2,
      width: scaledWidth,
      height: scaledHeight,
      child: cardWidget,
    );
  }

  Widget _buildPositionIndicator(
    BuildContext context,
    int currentIndex,
    int totalCards,
  ) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      label: 'Card ${currentIndex + 1} of $totalCards',
      child: AnimatedContainer(
        duration: AppMotion.quick,
        curve: AppMotion.standardCurve,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          '${currentIndex + 1} / $totalCards',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildCard(CardData card, bool isFocused) {
    final configuredBank = card.bankId != null
        ? Banks.getById(card.bankId!)
        : null;
    final network = _detectNetwork(card.cardType);
    final bank =
        configuredBank ??
        (network == CardNetwork.amex ? Banks.getById('amex') : null);
    final design = card.designId != null
        ? CardDesigns.getById(card.designId!)
        : null;

    final primaryColor = card.customGradientStartColor != null
        ? Color(card.customGradientStartColor!)
        : design?.primaryColor ?? bank?.primaryColor ?? Colors.grey.shade600;
    final secondaryColor = card.customGradientEndColor != null
        ? Color(card.customGradientEndColor!)
        : design?.secondaryColor ??
              bank?.secondaryColor ??
              Colors.grey.shade700;
    final hasCircles = design?.hasCircles ?? false;
    final foregroundColor =
        design?.foregroundColor ??
        (card.customBackgroundImagePath?.isNotEmpty == true
            ? CardContrast.ivory
            : CardContrast.bestForeground([primaryColor, secondaryColor]));

    String bankName = bank?.name ?? '';
    String cardName = card.cardNickname ?? card.categoryName;

    final cachedData = card.id != null ? _cardDataCache[card.id!] : null;

    final walletCard = _WalletCardCompact(
      bank: bank,
      bankName: bankName,
      cardName: cardName,
      maskedNumber: card.maskedCardNumber,
      network: network,
      design: design,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      foregroundColor: foregroundColor,
      showCircles: hasCircles,
      isFocused: isFocused,
      cardData: card,
      cardholderName: cachedData?.cardholderName,
      expiryDate: cachedData?.expiryDate,
    );

    if (!widget.selectionMode) {
      if (isFocused && card.id != null && !AppMotion.reduceMotion(context)) {
        return WalletCardHero(tag: 'wallet-card-${card.id}', child: walletCard);
      }
      return walletCard;
    }

    final isSelected =
        card.id != null && widget.selectedCardIds.contains(card.id);
    return Stack(
      children: [
        walletCard,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 14,
          right: 14,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.black.withValues(alpha: 0.38),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : null,
          ),
        ),
      ],
    );
  }

  CardNetwork _detectNetwork(String cardType) =>
      CardNetworkUtils.networkFromCardType(cardType);
}

class _CardRenderData {
  final int realIndex;
  final int virtualIndex;
  final double diff;
  final double scale;
  final double yPosition;
  final double cardHeight;
  final double cardWidth;
  final double horizontalPadding;
  final double opacity;
  final bool isFocused;

  _CardRenderData({
    required this.realIndex,
    required this.virtualIndex,
    required this.diff,
    required this.scale,
    required this.yPosition,
    required this.cardHeight,
    required this.cardWidth,
    required this.horizontalPadding,
    required this.opacity,
    required this.isFocused,
  });
}

class _WalletCardCompact extends StatelessWidget {
  final BankInfo? bank;
  final String bankName;
  final String cardName;
  final String maskedNumber;
  final CardNetwork network;
  final CardDesign? design;
  final Color primaryColor;
  final Color secondaryColor;
  final Color foregroundColor;
  final bool showCircles;
  final bool isFocused;
  final CardData cardData;
  final String? cardholderName;
  final String? expiryDate;

  const _WalletCardCompact({
    this.bank,
    required this.bankName,
    required this.cardName,
    required this.maskedNumber,
    required this.network,
    this.design,
    required this.primaryColor,
    required this.secondaryColor,
    required this.foregroundColor,
    this.showCircles = false,
    this.isFocused = false,
    required this.cardData,
    this.cardholderName,
    this.expiryDate,
  });

  bool get _isLightBackground => primaryColor.computeLuminance() > 0.5;
  Color get _textColor => foregroundColor;
  Color get _textColorSecondary => CardContrast.secondary(foregroundColor);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isFocused ? 0.25 : 0.12),
            blurRadius: isFocused ? 25 : 12,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: CardBackgroundSurface(
        design: design,
        customGradientStartColor: cardData.customGradientStartColor,
        customGradientEndColor: cardData.customGradientEndColor,
        customGradientAngle: cardData.customGradientAngle,
        customBackgroundImagePath: cardData.customBackgroundImagePath,
        backgroundImageBlur: cardData.backgroundImageBlur,
        fallbackPrimaryColor: primaryColor,
        fallbackSecondaryColor: secondaryColor,
        borderRadius: BorderRadius.circular(16),
        showShadow: false,
        child: Stack(
          children: [
            if (showCircles) _buildDecoCircles(),
            _buildContent(),
            if (bank != null) _buildBankLogo(),
            _buildNetworkLogo(),
            _buildCardHeader(),
            _buildCategoryLabel(),
          ],
        ),
      ),
    );
  }

  Widget _buildDecoCircles() {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final circleSize = constraints.maxHeight * 0.65;
          final circleColor = _isLightBackground
              ? const Color(0xFFE85D3F)
              : Colors.white;
          return Stack(
            children: [
              Positioned(
                left: constraints.maxWidth * 0.08,
                top: (constraints.maxHeight - circleSize) / 2,
                child: Container(
                  width: circleSize,
                  height: circleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: circleColor.withValues(alpha: 0.35),
                  ),
                ),
              ),
              Positioned(
                left: constraints.maxWidth * 0.08 + circleSize * 0.55,
                top: (constraints.maxHeight - circleSize) / 2,
                child: Container(
                  width: circleSize,
                  height: circleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: circleColor.withValues(alpha: 0.25),
                  ),
                ),
              ),
              Positioned(
                left: constraints.maxWidth * 0.08 + circleSize * 1.1,
                top: (constraints.maxHeight - circleSize) / 2,
                child: Container(
                  width: circleSize,
                  height: circleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: circleColor.withValues(alpha: 0.15),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 38, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildCardNumber(),
          const SizedBox(height: 6),
          if (cardholderName != null && cardholderName!.isNotEmpty)
            _buildCardholderName(),
          const SizedBox(height: 4),
          if (expiryDate != null && expiryDate!.isNotEmpty) _buildExpiryDate(),
        ],
      ),
    );
  }

  Widget _buildCardHeader() {
    return Positioned(
      top: 16,
      right: 16,
      child: Text(
        cardName,
        style: AppTypography.label(fontSize: 12, color: _textColor),
      ),
    );
  }

  Widget _buildCardNumber() {
    return Text(
      maskedNumber,
      style: AppTypography.mono(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: _textColor,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildCardholderName() {
    return Text(
      cardholderName!.toUpperCase(),
      style: AppTypography.overline(color: _textColorSecondary)
          .copyWith(letterSpacing: 0.5),
    );
  }

  Widget _buildExpiryDate() {
    return Row(
      children: [
        Text(
          'VALID THRU ',
          style: AppTypography.overline(
            fontSize: 8,
            color: _textColorSecondary,
          ).copyWith(letterSpacing: 0.5),
        ),
        Text(
          expiryDate!,
          style: AppTypography.mono(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: _textColor,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryLabel() {
    final categoryText = cardData.cardCategory == CardCategory.credit
        ? 'CREDIT CARD'
        : 'DEBIT CARD';

    return Positioned(
      right: -12,
      top: 0,
      bottom: 0,
      child: Center(
        child: Transform.rotate(
          angle: 1.5708,
          child: Text(
            categoryText,
            style: AppTypography.overline(
              fontSize: 8,
              color: _textColorSecondary.withValues(alpha: 0.6),
            ).copyWith(fontWeight: FontWeight.w600, letterSpacing: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildBankLogo() {
    if (bank == null) return const SizedBox.shrink();

    return Positioned(
      top: 12,
      left: 12,
      child: BankLogo(
        bank: bank,
        size: 22,
        useSmall: false,
        backgroundColor: primaryColor,
        foregroundColor: foregroundColor,
        maxWidth: 96,
      ),
    );
  }

  Widget _buildNetworkLogo() {
    return Positioned(
      bottom: 14,
      right: 14,
      child: CardNetworkLogo(
        cardNumber: '',
        forceNetwork: network,
        height: 28,
        backgroundColor: primaryColor,
      ),
    );
  }
}

class BottomActionBar extends StatelessWidget {
  final VoidCallback? onAddCard;

  const BottomActionBar({super.key, this.onAddCard});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: onAddCard,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.add, color: Colors.black, size: 22),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add Card',
              style: AppTypography.caption(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

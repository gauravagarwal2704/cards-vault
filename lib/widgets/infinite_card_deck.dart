import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/card_data.dart';
import '../data/banks.dart';
import '../data/card_designs.dart';
import 'wallet_card.dart';
import 'bank_logo.dart';
import 'card_network_logo.dart';
import 'swipeable_card.dart';
import '../theme/app_typography.dart';
import '../utils/card_network_utils.dart';

class InfiniteCardDeck extends StatefulWidget {
  final List<CardData> cards;
  final Function(CardData card)? onCardTap;
  final Function(CardData card)? onCardLongPress;
  final Function(int index)? onCardChanged;
  final Function(CardData card)? onCardShare;
  final Function(CardData card)? onCardDelete;
  final int initialIndex;

  const InfiniteCardDeck({
    super.key,
    required this.cards,
    this.onCardTap,
    this.onCardLongPress,
    this.onCardChanged,
    this.onCardShare,
    this.onCardDelete,
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
  double _animStartIndex = 0;
  double _dragStartY = 0;
  double _dragStartIndex = 0;
  bool _isDragging = false;
  bool _isHorizontalSwipeActive = false;
  int _lastHapticIndex = 0;

  // Credit card aspect ratio: 85.6mm x 53.98mm = 1.586:1
  static const double _cardAspectRatio = 1.586;
  static const double _cardWidthPercent = 0.85;
  // How much of each stacked card peeks out (as fraction of card height)
  // Range: 20-25% for visible stacking
  static const double _peekPercent = 0.22;

  int _lastReportedIndex = 0;
  
  final Map<String, _DecryptedCardData> _cardDataCache = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.toDouble();
    _targetIndex = _currentIndex;
    _animStartIndex = _currentIndex;
    _lastReportedIndex = widget.initialIndex;
    _lastHapticIndex = widget.initialIndex;
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animationController.addListener(_onAnimationUpdate);
    _animationController.addStatusListener(_onAnimationStatus);
    _preloadCardData();
  }
  
  Future<void> _preloadCardData() async {
    for (final card in widget.cards) {
      if (card.id != null && !_cardDataCache.containsKey(card.id)) {
        final cardholder = await card.getDecryptedCardholderName();
        final expiry = await card.getDecryptedExpiryDate();
        if (mounted) {
          setState(() {
            _cardDataCache[card.id!] = _DecryptedCardData(
              cardholderName: cardholder,
              expiryDate: expiry,
            );
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _animationController.removeListener(_onAnimationUpdate);
    _animationController.removeStatusListener(_onAnimationStatus);
    _animationController.dispose();
    super.dispose();
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      HapticFeedback.lightImpact();
      final currentIdx = _targetIndex.round() % widget.cards.length;
      if (currentIdx != _lastReportedIndex) {
        _lastReportedIndex = currentIdx;
        widget.onCardChanged?.call(currentIdx);
      }
    }
  }

  void _onAnimationUpdate() {
    if (!_isDragging) {
      setState(() {
        _currentIndex = lerpDouble(
          _animStartIndex,
          _targetIndex,
          Curves.easeOutCubic.transform(_animationController.value),
        )!;
      });
    }
  }

  void _animateToIndex(double target) {
    _animStartIndex = _currentIndex;
    _targetIndex = target;
    _animationController.reset();
    _animationController.forward();
  }

  void _onPanStart(DragStartDetails details) {
    if (_isHorizontalSwipeActive) return;
    _isDragging = true;
    _animationController.stop();
    _dragStartY = details.localPosition.dy;
    _dragStartIndex = _currentIndex;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_isHorizontalSwipeActive) return;
    final delta = details.localPosition.dy - _dragStartY;
    final newIndex = _dragStartIndex - (delta / 120);
    final newRoundedIndex = newIndex.round();
    
    if (newRoundedIndex != _lastHapticIndex) {
      _lastHapticIndex = newRoundedIndex;
      HapticFeedback.selectionClick();
    }
    
    setState(() {
      _currentIndex = newIndex;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isHorizontalSwipeActive) return;
    _isDragging = false;
    final velocity = details.velocity.pixelsPerSecond.dy;
    
    double target;
    if (velocity.abs() > 500) {
      final cardsMoved = (-velocity / 600).round().clamp(-2, 2);
      target = (_currentIndex + cardsMoved).roundToDouble();
    } else {
      target = _currentIndex.roundToDouble();
    }
    
    _animateToIndex(target);
  }

  void _onCardTapped(int virtualIndex) {
    _animateToIndex(virtualIndex.toDouble());
  }

  int _getRealIndex(int virtualIndex) {
    if (widget.cards.isEmpty) return 0;
    return ((virtualIndex % widget.cards.length) + widget.cards.length) % widget.cards.length;
  }

  double _getRandomTilt(int index) {
    // Tilt disabled temporarily
    return 0.0;
    // final random = math.Random(index * 31);
    // final baseTilt = (random.nextDouble() - 0.5) * 0.08;
    // final extraTilt = baseTilt * (1.0 + random.nextDouble() * 0.2);
    // return extraTilt;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) {
      return const SizedBox.shrink();
    }

    return ClipRect(
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        behavior: HitTestBehavior.opaque,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth * _cardWidthPercent;
            final cardHeight = cardWidth / _cardAspectRatio;
            final centerY = (constraints.maxHeight - cardHeight) / 2;
            final horizontalPadding = (constraints.maxWidth - cardWidth) / 2;
            final peekAmount = cardHeight * _peekPercent;
            
            final totalCards = widget.cards.length;
            final cardsAbove = (totalCards - 1) ~/ 2;
            final cardsBelow = totalCards - 1 - cardsAbove;
            
            List<_CardRenderData> cardsToRender = [];
            
            // Render all cards based on their continuous position relative to _currentIndex
            for (int offset = -cardsAbove; offset <= cardsBelow; offset++) {
              final virtualIndex = _currentIndex.round() + offset;
              final realIndex = _getRealIndex(virtualIndex);
              
              // Calculate continuous difference from current scroll position
              final diff = virtualIndex - _currentIndex;
              
              cardsToRender.add(_calculateCardData(
                virtualIndex: virtualIndex,
                realIndex: realIndex,
                diff: diff,
                centerY: centerY,
                cardHeight: cardHeight,
                cardWidth: cardWidth,
                horizontalPadding: horizontalPadding,
                peekAmount: peekAmount,
              ));
            }
            
            // Sort by z-order: cards furthest from center render first (behind)
            cardsToRender.sort((a, b) => b.diff.abs().compareTo(a.diff.abs()));

            return Stack(
              clipBehavior: Clip.hardEdge,
              children: cardsToRender.map((data) => _buildCardWidget(data)).toList(),
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
    double blur;
    double opacity;
    double tilt;
    
    if (absDiff < 0.01) {
      // Exactly focused
      scale = 1.0;
      yOffset = 0;
      blur = 0;
      opacity = 1.0;
      tilt = 0;
    } else {
      // Scale decreases smoothly as card moves away from center
      scale = (1.0 - absDiff * 0.03).clamp(0.88, 1.0);
      
      // Position: cards stack with equal gaps above/below center card
      // Each card peeks out by peekAmount
      yOffset = diff * peekAmount;
      
      blur = (absDiff * 0.8).clamp(0.0, 2.5);
      opacity = (1.0 - absDiff * 0.1).clamp(0.7, 1.0);
      tilt = _getRandomTilt(virtualIndex) * (absDiff.clamp(0.0, 1.0));
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
      blur: blur,
      opacity: opacity,
      tilt: tilt,
      isFocused: isFocused,
    );
  }

  Widget _buildCardWidget(_CardRenderData data) {
    final card = widget.cards[data.realIndex];
    
    final scaledWidth = data.cardWidth * data.scale;
    final scaledHeight = data.cardHeight * data.scale;
    final leftOffset = data.horizontalPadding + (data.cardWidth - scaledWidth) / 2;
    
    Widget cardWidget = GestureDetector(
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
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateZ(data.tilt),
        child: Opacity(
          opacity: data.opacity.clamp(0.0, 1.0),
          child: data.blur > 0.1
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: data.blur,
                      sigmaY: data.blur,
                    ),
                    child: _buildCard(card, data.isFocused),
                  ),
                )
              : _buildCard(card, data.isFocused),
        ),
      ),
    );

    // Wrap focused card with SwipeableCard
    if (data.isFocused) {
      cardWidget = SwipeableCard(
        cardWidth: scaledWidth,
        cardHeight: scaledHeight,
        onShare: () => widget.onCardShare?.call(widget.cards[data.realIndex]),
        onDelete: () => widget.onCardDelete?.call(widget.cards[data.realIndex]),
        child: cardWidget,
      );
    }
    
    return Positioned(
      left: leftOffset,
      top: data.yPosition + (data.cardHeight - scaledHeight) / 2,
      width: scaledWidth,
      height: scaledHeight,
      child: cardWidget,
    );
  }

  Widget _buildCard(CardData card, bool isFocused) {
    final bank = card.bankId != null ? Banks.getById(card.bankId!) : null;
    final design = card.designId != null ? CardDesigns.getById(card.designId!) : null;
    
    final primaryColor = design?.primaryColor ?? bank?.primaryColor ?? Colors.grey.shade600;
    final secondaryColor = design?.secondaryColor ?? bank?.secondaryColor ?? Colors.grey.shade700;
    final hasCircles = design?.hasCircles ?? false;
    
    final network = _detectNetwork(card.cardType);
    
    String bankName = bank?.name ?? '';
    String cardName = card.cardNickname ?? card.categoryName;
    
    final cachedData = card.id != null ? _cardDataCache[card.id!] : null;
    
    return _WalletCardCompact(
      bank: bank,
      bankName: bankName,
      cardName: cardName,
      maskedNumber: card.maskedCardNumber,
      network: network,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      showCircles: hasCircles,
      isFocused: isFocused,
      cardData: card,
      cardholderName: cachedData?.cardholderName,
      expiryDate: cachedData?.expiryDate,
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
  final double blur;
  final double opacity;
  final double tilt;
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
    required this.blur,
    required this.opacity,
    required this.tilt,
    required this.isFocused,
  });
}

class _WalletCardCompact extends StatelessWidget {
  final BankInfo? bank;
  final String bankName;
  final String cardName;
  final String maskedNumber;
  final CardNetwork network;
  final Color primaryColor;
  final Color secondaryColor;
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
    required this.primaryColor,
    required this.secondaryColor,
    this.showCircles = false,
    this.isFocused = false,
    required this.cardData,
    this.cardholderName,
    this.expiryDate,
  });
  
  bool get _isLightBackground => primaryColor.computeLuminance() > 0.5;
  Color get _textColor => _isLightBackground ? Colors.black87 : Colors.white;
  Color get _textColorSecondary => _isLightBackground ? Colors.black54 : Colors.white70;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primaryColor, secondaryColor],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isFocused ? 0.25 : 0.12),
            blurRadius: isFocused ? 25 : 12,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.hardEdge,
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
                    color: circleColor.withOpacity(0.35),
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
                    color: circleColor.withOpacity(0.25),
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
                    color: circleColor.withOpacity(0.15),
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
          if (expiryDate != null && expiryDate!.isNotEmpty)
            _buildExpiryDate(),
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
      style: AppTypography.overline(color: _textColorSecondary).copyWith(
        letterSpacing: 0.5,
      ),
    );
  }
  
  Widget _buildExpiryDate() {
    return Row(
      children: [
        Text(
          'VALID THRU ',
          style: AppTypography.overline(fontSize: 8, color: _textColorSecondary).copyWith(
            letterSpacing: 0.5,
          ),
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
              color: _textColorSecondary.withOpacity(0.6),
            ).copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
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
        isInputField: false,
        backgroundColor: primaryColor,
      ),
    );
  }
}

class BottomActionBar extends StatelessWidget {
  final VoidCallback? onAddCard;

  const BottomActionBar({
    super.key,
    this.onAddCard,
  });

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
                      color: Colors.black.withOpacity(0.1),
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

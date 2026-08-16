import 'package:flutter/material.dart';

import '../data/banks.dart';
import '../data/card_designs.dart';
import '../models/card_data.dart';
import '../theme/app_typography.dart';
import '../theme/app_motion.dart';
import '../utils/card_network_utils.dart';
import '../utils/card_contrast.dart';
import 'bank_logo.dart';
import 'card_background_surface.dart';
import 'card_network_logo.dart';

const _tileAspectRatio = 1.586;
const _tileSpacing = 12.0;
const _gridPadding = EdgeInsets.fromLTRB(20, 8, 20, 120);

class CardTilesGrid extends StatelessWidget {
  final List<CardData> cards;
  final ValueChanged<CardData>? onCardTap;
  final ValueChanged<CardData>? onCardLongPress;
  final Set<String> selectedCardIds;
  final bool selectionMode;

  const CardTilesGrid({
    super.key,
    required this.cards,
    this.onCardTap,
    this.onCardLongPress,
    this.selectedCardIds = const {},
    this.selectionMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: _gridPadding,
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: _tileSpacing,
        mainAxisSpacing: _tileSpacing,
        childAspectRatio: _tileAspectRatio,
      ),
      itemBuilder: (context, index) => CardTile(
        card: cards[index],
        onTap: onCardTap,
        onLongPress: onCardLongPress,
        isSelected:
            cards[index].id != null &&
            selectedCardIds.contains(cards[index].id),
        selectionMode: selectionMode,
      ),
    );
  }
}

class CardTile extends StatelessWidget {
  final CardData card;
  final ValueChanged<CardData>? onTap;
  final ValueChanged<CardData>? onLongPress;
  final bool isSelected;
  final bool selectionMode;

  const CardTile({
    super.key,
    required this.card,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.selectionMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final bank = card.bankId != null ? Banks.getById(card.bankId!) : null;
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
    final textColor =
        design?.foregroundColor ??
        (card.customBackgroundImagePath?.isNotEmpty == true
            ? CardContrast.ivory
            : CardContrast.bestForeground([primaryColor, secondaryColor]));
    final subtleColor = CardContrast.secondary(textColor);

    return PressableScale(
      child: Semantics(
        button: onTap != null,
        selected: isSelected,
        label: '${card.categoryName} card ending ${card.lastFourDigits}',
        child: GestureDetector(
          onTap: onTap == null ? null : () => onTap!(card),
          onLongPress: onLongPress == null ? null : () => onLongPress!(card),
          child: HeroMode(
            enabled:
                !selectionMode &&
                card.id != null &&
                !AppMotion.reduceMotion(context),
            child: Hero(
              tag: 'wallet-card-${card.id ?? card.hashCode}',
              child: Stack(
                children: [
                  AnimatedContainer(
                    duration: AppMotion.quick,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: CardBackgroundSurface(
                      design: design,
                      customGradientStartColor: card.customGradientStartColor,
                      customGradientEndColor: card.customGradientEndColor,
                      customGradientAngle: card.customGradientAngle,
                      customBackgroundImagePath: card.customBackgroundImagePath,
                      backgroundImageBlur: card.backgroundImageBlur,
                      fallbackPrimaryColor: primaryColor,
                      fallbackSecondaryColor: secondaryColor,
                      borderRadius: BorderRadius.circular(14),
                      showShadow: false,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (bank != null)
                              BankLogo(
                                bank: bank,
                                size: 18,
                                useSmall: false,
                                backgroundColor: primaryColor,
                                foregroundColor: textColor,
                                maxWidth: 76,
                              ),
                            const Spacer(),
                            Text(
                              card.cardNickname?.isNotEmpty == true
                                  ? card.cardNickname!
                                  : card.categoryName,
                              style: AppTypography.label(
                                fontSize: 11,
                                color: textColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Text(
                                    '•••• ${card.lastFourDigits}',
                                    style: AppTypography.mono(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: subtleColor,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                CardNetworkLogo(
                                  cardNumber: '',
                                  forceNetwork:
                                      CardNetworkUtils.networkFromCardType(
                                        card.cardType,
                                      ),
                                  height: 18,
                                  isInputField: false,
                                  backgroundColor: primaryColor,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (selectionMode)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: AnimatedContainer(
                        duration: AppMotion.quick,
                        width: 27,
                        height: 27,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.black.withValues(alpha: 0.38),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 18,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../data/banks.dart';
import '../data/card_designs.dart';
import '../models/card_data.dart';
import '../theme/app_typography.dart';
import '../utils/card_network_utils.dart';
import 'bank_logo.dart';
import 'card_network_logo.dart';

const _tileAspectRatio = 1.586;
const _tileSpacing = 12.0;
const _gridPadding = EdgeInsets.fromLTRB(20, 8, 20, 120);

class CardTilesGrid extends StatelessWidget {
  final List<CardData> cards;
  final ValueChanged<CardData>? onCardTap;
  final ValueChanged<CardData>? onCardLongPress;

  const CardTilesGrid({
    super.key,
    required this.cards,
    this.onCardTap,
    this.onCardLongPress,
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
      ),
    );
  }
}

class CardTile extends StatelessWidget {
  final CardData card;
  final ValueChanged<CardData>? onTap;
  final ValueChanged<CardData>? onLongPress;

  const CardTile({
    super.key,
    required this.card,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final bank = card.bankId != null ? Banks.getById(card.bankId!) : null;
    final design =
        card.designId != null ? CardDesigns.getById(card.designId!) : null;

    final primaryColor =
        design?.primaryColor ?? bank?.primaryColor ?? Colors.grey.shade600;
    final secondaryColor =
        design?.secondaryColor ?? bank?.secondaryColor ?? Colors.grey.shade700;
    final isLight = primaryColor.computeLuminance() > 0.5;
    final textColor = isLight ? Colors.black87 : Colors.white;
    final subtleColor = isLight ? Colors.black54 : Colors.white70;

    return GestureDetector(
      onTap: onTap == null ? null : () => onTap!(card),
      onLongPress: onLongPress == null ? null : () => onLongPress!(card),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primaryColor, secondaryColor],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
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
                    maxWidth: 76,
                  ),
                const Spacer(),
                Text(
                  card.cardNickname?.isNotEmpty == true
                      ? card.cardNickname!
                      : card.categoryName,
                  style: AppTypography.label(fontSize: 11, color: textColor),
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
                      forceNetwork: CardNetworkUtils.networkFromCardType(
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
    );
  }
}

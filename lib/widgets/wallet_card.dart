import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'card_network_logo.dart';
import 'bank_logo.dart';
import '../models/card_data.dart';
import '../data/banks.dart';
import '../data/card_designs.dart';
import '../providers/theme_provider.dart';
import '../theme/app_typography.dart';
import '../utils/card_contrast.dart';
import 'card_background_surface.dart';

enum CardNetwork {
  visa,
  mastercard,
  amex,
  discover,
  jcb,
  dinersClub,
  unionPay,
  gpay,
  rupay,
  maestro,
  unknown,
}

class WalletCardData {
  final String cardTypePrefix;
  final String cardTypeSuffix;
  final CardNetwork network;
  final String balance;
  final String balanceCents;
  final String cardNumber;
  final Color primaryColor;
  final Color? secondaryColor;
  final bool showMastercardCircles;

  const WalletCardData({
    required this.cardTypePrefix,
    this.cardTypeSuffix = 'Card',
    required this.network,
    this.balance = '',
    this.balanceCents = '',
    required this.cardNumber,
    required this.primaryColor,
    this.secondaryColor,
    this.showMastercardCircles = false,
  });
}

class WalletCard extends StatelessWidget {
  final WalletCardData? data;
  final CardData? cardData;
  final BankInfo? bank;
  final String? cardholderName;
  final bool isFocused;
  final VoidCallback? onTap;

  const WalletCard({
    super.key,
    this.data,
    this.cardData,
    this.bank,
    this.cardholderName,
    this.isFocused = false,
    this.onTap,
  }) : assert(
         data != null || cardData != null,
         'Either data or cardData must be provided',
       );

  @override
  Widget build(BuildContext context) {
    final primaryColor = _getPrimaryColor(context);
    final secondaryColor = _getSecondaryColor(context);
    final design = cardData?.designId == null
        ? null
        : CardDesigns.getById(cardData!.designId!);
    final foregroundColor =
        design?.foregroundColor ??
        (cardData?.customBackgroundImagePath?.isNotEmpty == true
            ? CardContrast.ivory
            : CardContrast.bestForeground([primaryColor, secondaryColor]));

    return Semantics(
      button: onTap != null,
      label: cardData == null
          ? 'Payment card'
          : '${cardData!.categoryName} card ending ${cardData!.lastFourDigits}',
      child: GestureDetector(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 1.586,
          child: CardBackgroundSurface(
            design: design,
            customGradientStartColor: cardData?.customGradientStartColor,
            customGradientEndColor: cardData?.customGradientEndColor,
            customGradientAngle: cardData?.customGradientAngle ?? 135,
            customBackgroundImagePath: cardData?.customBackgroundImagePath,
            backgroundImageBlur: cardData?.backgroundImageBlur ?? 0,
            fallbackPrimaryColor: primaryColor,
            fallbackSecondaryColor: secondaryColor,
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                if (_shouldShowMastercardCircles() &&
                    design == null &&
                    cardData?.customGradientStartColor == null &&
                    cardData?.customBackgroundImagePath == null)
                  _buildMastercardCircles(),
                _buildCardContent(foregroundColor),
                _buildNetworkLogo(),
                if (bank != null) _buildBankLogo(primaryColor, foregroundColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getPrimaryColor(BuildContext context) {
    if (data != null) return data!.primaryColor;
    if (cardData?.customGradientStartColor != null) {
      return Color(cardData!.customGradientStartColor!);
    }
    final designId = cardData?.designId;
    final design = designId == null ? null : CardDesigns.getById(designId);
    if (design != null) return design.primaryColor;
    if (bank != null) return bank!.primaryColor;
    return context.watch<ThemeProvider>().getPrimaryColor();
  }

  Color _getSecondaryColor(BuildContext context) {
    if (data != null) {
      return data!.secondaryColor ??
          Color.lerp(data!.primaryColor, Colors.black, 0.15)!;
    }
    if (cardData?.customGradientEndColor != null) {
      return Color(cardData!.customGradientEndColor!);
    }
    final designId = cardData?.designId;
    final design = designId == null ? null : CardDesigns.getById(designId);
    if (design != null) return design.secondaryColor;
    if (bank != null) return bank!.secondaryColor;
    return context.watch<ThemeProvider>().getPrimaryContainerColor();
  }

  bool _shouldShowMastercardCircles() {
    if (data != null) return data!.showMastercardCircles;
    if (cardData != null) {
      return cardData!.cardType.toLowerCase() == 'mastercard';
    }
    return false;
  }

  Widget _buildMastercardCircles() {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final circleSize = constraints.maxHeight * 0.6;
          return Stack(
            children: [
              Positioned(
                left: 24,
                top: (constraints.maxHeight - circleSize) / 2 + 10,
                child: Container(
                  width: circleSize,
                  height: circleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE85D3F).withValues(alpha: 0.9),
                  ),
                ),
              ),
              Positioned(
                left: 24 + circleSize * 0.6,
                top: (constraints.maxHeight - circleSize) / 2 + 10,
                child: Container(
                  width: circleSize,
                  height: circleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE85D3F).withValues(alpha: 0.7),
                  ),
                ),
              ),
              Positioned(
                left: 24 + circleSize * 1.2,
                top: (constraints.maxHeight - circleSize) / 2 + 10,
                child: Container(
                  width: circleSize,
                  height: circleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE85D3F).withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCardContent(Color foregroundColor) {
    final secondaryForeground = CardContrast.secondary(foregroundColor);
    final tertiaryForeground = CardContrast.tertiary(foregroundColor);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: _buildCardTypeLabel(foregroundColor)),
              _buildContactlessIcon(secondaryForeground),
            ],
          ),
          const Spacer(),
          if (cardData != null) ...[
            Text(
              cardData!.maskedCardNumber,
              style: AppTypography.mono(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: secondaryForeground,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            if (cardholderName != null && cardholderName!.isNotEmpty)
              Text(
                cardholderName!.toUpperCase(),
                style: AppTypography.overline(
                  fontSize: 11,
                  color: tertiaryForeground,
                ),
              ),
          ] else if (data != null) ...[
            Text(
              data!.cardNumber,
              style: AppTypography.mono(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: secondaryForeground,
                letterSpacing: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCardTypeLabel(Color foregroundColor) {
    final secondaryForeground = CardContrast.secondary(foregroundColor);
    final tertiaryForeground = CardContrast.tertiary(foregroundColor);
    if (cardData != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                cardData!.categoryName,
                style: AppTypography.cardName(color: foregroundColor),
              ),
              Text(
                ' Card',
                style: AppTypography.cardNameLight(color: secondaryForeground),
              ),
            ],
          ),
          if (cardData!.cardNickname != null &&
              cardData!.cardNickname!.isNotEmpty)
            Text(
              cardData!.cardNickname!,
              style: AppTypography.overline(color: tertiaryForeground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      );
    }

    return Row(
      children: [
        Text(
          data!.cardTypePrefix,
          style: AppTypography.cardName(fontSize: 16, color: foregroundColor),
        ),
        Text(
          data!.cardTypeSuffix,
          style: AppTypography.cardNameLight(
            fontSize: 16,
            color: secondaryForeground,
          ),
        ),
      ],
    );
  }

  Widget _buildContactlessIcon(Color color) {
    return Icon(Icons.contactless, color: color, size: 26);
  }

  Widget _buildBankLogo(Color primaryColor, Color foregroundColor) {
    if (bank == null) return const SizedBox.shrink();

    return Positioned(
      top: 16,
      right: 16,
      child: BankLogo(
        bank: bank,
        size: 48,
        useSmall: false,
        backgroundColor: primaryColor,
        foregroundColor: foregroundColor,
        maxWidth: 130,
      ),
    );
  }

  Widget _buildNetworkLogo() {
    if (cardData == null) {
      return Positioned(top: 14, right: 54, child: _getNetworkWidget());
    }
    return const SizedBox.shrink();
  }

  Widget _getNetworkWidget() {
    if (data != null) {
      return CardNetworkLogo(
        cardNumber: data!.cardNumber.replaceAll('•', ''),
        forceNetwork: data!.network,
        height: 28,
      );
    }
    return const SizedBox.shrink();
  }
}

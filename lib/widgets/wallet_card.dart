import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'card_network_logo.dart';
import 'bank_logo.dart';
import '../models/card_data.dart';
import '../data/banks.dart';
import '../providers/theme_provider.dart';
import '../theme/app_typography.dart';

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
  }) : assert(data != null || cardData != null, 'Either data or cardData must be provided');

  @override
  Widget build(BuildContext context) {
    final primaryColor = _getPrimaryColor(context);
    final secondaryColor = _getSecondaryColor(context);
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
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
              blurRadius: isFocused ? 30 : 15,
              spreadRadius: 0,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.hardEdge,
          child: AspectRatio(
            aspectRatio: 1.586,
            child: Stack(
              children: [
                if (_shouldShowMastercardCircles()) _buildMastercardCircles(),
                _buildCardContent(),
                _buildNetworkLogo(),
                if (bank != null) _buildBankLogo(primaryColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Color _getPrimaryColor(BuildContext context) {
    if (data != null) return data!.primaryColor;
    if (bank != null) return bank!.primaryColor;
    return context.watch<ThemeProvider>().getPrimaryColor();
  }
  
  Color _getSecondaryColor(BuildContext context) {
    if (data != null) {
      return data!.secondaryColor ?? Color.lerp(data!.primaryColor, Colors.black, 0.15)!;
    }
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
                    color: const Color(0xFFE85D3F).withOpacity(0.9),
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
                    color: const Color(0xFFE85D3F).withOpacity(0.7),
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
                    color: const Color(0xFFE85D3F).withOpacity(0.5),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCardContent() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: _buildCardTypeLabel()),
              _buildContactlessIcon(),
            ],
          ),
          const Spacer(),
          if (cardData != null) ...[
            Text(
              cardData!.maskedCardNumber,
              style: AppTypography.mono(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: Colors.white70,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            if (cardholderName != null && cardholderName!.isNotEmpty)
              Text(
                cardholderName!.toUpperCase(),
                style: AppTypography.overline(
                  fontSize: 11,
                  color: Colors.white60,
                ),
              ),
          ] else if (data != null) ...[
            Text(
              data!.cardNumber,
              style: AppTypography.mono(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: Colors.black54,
                letterSpacing: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCardTypeLabel() {
    if (cardData != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                cardData!.categoryName,
                style: AppTypography.cardName(color: Colors.white),
              ),
              Text(
                ' Card',
                style: AppTypography.cardNameLight(color: Colors.white70),
              ),
            ],
          ),
          if (cardData!.cardNickname != null && cardData!.cardNickname!.isNotEmpty)
            Text(
              cardData!.cardNickname!,
              style: AppTypography.overline(color: Colors.white60),
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
          style: AppTypography.cardName(fontSize: 16, color: Colors.black87),
        ),
        Text(
          data!.cardTypeSuffix,
          style: AppTypography.cardNameLight(fontSize: 16, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _buildContactlessIcon() {
    return Icon(
      Icons.contactless,
      color: cardData != null 
          ? Colors.white.withOpacity(0.7)
          : Colors.black.withOpacity(0.5),
      size: 26,
    );
  }
  
  Widget _buildBankLogo(Color primaryColor) {
    if (bank == null) return const SizedBox.shrink();
    
    return Positioned(
      top: 16,
      right: 16,
      child: BankLogo(
        bank: bank,
        size: 48,
        useSmall: false,
        backgroundColor: primaryColor,
        maxWidth: 130,
      ),
    );
  }

  Widget _buildNetworkLogo() {
    if (cardData == null) {
      return Positioned(
        top: 14,
        right: 54,
        child: _getNetworkWidget(),
      );
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

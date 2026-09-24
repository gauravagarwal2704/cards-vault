import 'package:flutter/material.dart';

import '../data/banks.dart';
import '../theme/app_typography.dart';
import '../utils/card_contrast.dart';
import 'bank_logo.dart';
import 'card_network_logo.dart';
import 'wallet_card.dart';

/// Shared full-size card face used by card forms and the card detail screen.
/// Keeping the content in one widget prevents saved cards and form previews
/// from drifting into different layouts.
class WalletCardFace extends StatelessWidget {
  const WalletCardFace({
    super.key,
    required this.bank,
    required this.network,
    required this.categoryName,
    required this.nickname,
    required this.cardNumber,
    required this.cardholderName,
    required this.expiryDate,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final BankInfo? bank;
  final CardNetwork network;
  final String categoryName;
  final String nickname;
  final String cardNumber;
  final String cardholderName;
  final String expiryDate;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final secondaryForeground = CardContrast.secondary(foregroundColor);
    final tertiaryForeground = CardContrast.tertiary(foregroundColor);
    final issuer =
        bank ?? (network == CardNetwork.amex ? Banks.getById('amex') : null);

    return Stack(
      children: [
        Positioned(
          left: 4,
          bottom: 22,
          child: RotatedBox(
            quarterTurns: 3,
            child: Text(
              '${categoryName.toUpperCase()} CARD',
              style: AppTypography.overline(
                fontSize: 9,
                color: tertiaryForeground,
              ).copyWith(fontWeight: FontWeight.w600, letterSpacing: 1.5),
            ),
          ),
        ),
        Positioned(
          right: 18,
          top: 0,
          bottom: 0,
          child: Center(
            child: Icon(
              Icons.contactless,
              color: secondaryForeground,
              size: 34,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(25, 22, 12, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: issuer == null
                          ? const SizedBox.shrink()
                          : BankLogo(
                              bank: issuer,
                              size: 30,
                              useSmall: false,
                              backgroundColor: backgroundColor,
                              foregroundColor: foregroundColor,
                              maxWidth: 150,
                            ),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        nickname,
                        style: AppTypography.label(
                          fontSize: 16,
                          color: secondaryForeground,
                        ),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Transform.translate(
                offset: const Offset(0, 12),
                child: Text(
                  cardNumber,
                  style: AppTypography.mono(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: foregroundColor,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              cardholderName.toUpperCase(),
                              style: AppTypography.label(
                                fontSize: 14,
                                color: foregroundColor,
                              ),
                              maxLines: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 28),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'VALID\nTHRU',
                              style: AppTypography.overline(
                                fontSize: 8,
                                color: tertiaryForeground,
                              ).copyWith(height: 1.2),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              expiryDate,
                              style: AppTypography.label(
                                fontSize: 12,
                                color: foregroundColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 64,
                    child: Align(
                      alignment: Alignment.bottomRight,
                      widthFactor: 1,
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          network == CardNetwork.rupay ? 0 : 16,
                        ),
                        child: CardNetworkLogo(
                          cardNumber: '',
                          forceNetwork: network,
                          height: 64,
                          maxWidth: 100,
                          backgroundColor: backgroundColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

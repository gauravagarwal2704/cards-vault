import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'wallet_card.dart';
import '../utils/card_network_utils.dart';

class CardNetworkLogo extends StatelessWidget {
  final String cardNumber;
  final double height;
  final CardNetwork? forceNetwork;
  final Color? backgroundColor;
  final double? maxWidth;

  const CardNetworkLogo({
    super.key,
    required this.cardNumber,
    this.height = 24,
    this.forceNetwork,
    this.backgroundColor,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final network = forceNetwork ?? CardNetworkUtils.detectNetwork(cardNumber);
    final logoPath = _getLogoPath(network);

    if (logoPath == null) {
      return SizedBox(height: height, width: height * 1.5);
    }

    final isDarkBackground =
        backgroundColor != null && backgroundColor!.computeLuminance() < 0.5;

    final isLightBackground =
        backgroundColor != null && backgroundColor!.computeLuminance() >= 0.5;

    final shouldApplyWhiteFilter =
        isDarkBackground && _shouldUseWhiteOnDark(network);
    final shouldApplyDarkFilter =
        isLightBackground && _shouldUseDarkOnLight(network);

    // Landscape assets (RuPay) blow past the caller's layout when sized by
    // height alone, so trade height away to respect the width budget.
    final widthCap = maxWidth ?? height * 1.6;
    final aspectRatio = _assetAspectRatio(network);
    final renderHeight = height * aspectRatio > widthCap
        ? widthCap / aspectRatio
        : height;

    return SvgPicture.asset(
      logoPath,
      height: renderHeight,
      fit: BoxFit.contain,
      colorFilter: shouldApplyWhiteFilter
          ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
          : shouldApplyDarkFilter
          ? ColorFilter.mode(Colors.grey.shade800, BlendMode.srcIn)
          : null,
    );
  }

  /// Width over height of the asset's viewBox. Every logo is square except
  /// RuPay's, which is a wide wordmark.
  double _assetAspectRatio(CardNetwork network) {
    return network == CardNetwork.rupay ? 512 / 138 : 1.0;
  }

  bool _shouldUseWhiteOnDark(CardNetwork network) {
    switch (network) {
      case CardNetwork.visa:
      case CardNetwork.discover:
      case CardNetwork.jcb:
      case CardNetwork.rupay:
      case CardNetwork.maestro:
      case CardNetwork.unionPay:
      case CardNetwork.dinersClub:
        return true;
      case CardNetwork.amex:
      case CardNetwork.mastercard:
      case CardNetwork.gpay:
      case CardNetwork.unknown:
        return false;
    }
  }

  bool _shouldUseDarkOnLight(CardNetwork network) {
    switch (network) {
      case CardNetwork.visa:
      case CardNetwork.amex:
      case CardNetwork.discover:
      case CardNetwork.jcb:
      case CardNetwork.rupay:
      case CardNetwork.maestro:
      case CardNetwork.unionPay:
      case CardNetwork.dinersClub:
        return false;
      case CardNetwork.mastercard:
      case CardNetwork.gpay:
      case CardNetwork.unknown:
        return false;
    }
  }

  String? _getLogoPath(CardNetwork network) {
    switch (network) {
      case CardNetwork.visa:
        return 'assets/networks/visa.svg';
      case CardNetwork.mastercard:
        return 'assets/networks/mastercard.svg';
      case CardNetwork.amex:
        return 'assets/networks/amex-small.svg';
      case CardNetwork.discover:
        return 'assets/networks/discover.svg';
      case CardNetwork.jcb:
        return 'assets/networks/jcb.svg';
      case CardNetwork.dinersClub:
        return 'assets/networks/diners-club.svg';
      case CardNetwork.unionPay:
        return 'assets/networks/union-pay.svg';
      case CardNetwork.rupay:
        return 'assets/networks/rupay.svg';
      case CardNetwork.maestro:
        return 'assets/networks/maestro.svg';
      case CardNetwork.gpay:
      case CardNetwork.unknown:
        return null;
    }
  }
}

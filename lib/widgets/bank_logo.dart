import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/banks.dart';
import '../theme/app_typography.dart';

class BankLogo extends StatelessWidget {
  static const String dummyLogoSmall = 'assets/banks-logo-small/dummy.svg';
  static const String dummyLogoLarge = 'assets/banks-logo-large/dummy.svg';

  /// Large logos that are wide wordmarks rather than square marks. Tinting them
  /// white collapses the artwork into a solid block, so they render untinted.
  /// Values are the asset aspect ratios (every large logo is 24 units tall),
  /// used to give the wordmark a correctly proportioned box rather than a
  /// square one.
  static const Map<String, double> _wideLogoAspectRatios = {
    'hdfc': 139 / 24,
    'icici': 120 / 24,
    'federal': 78 / 24,
    'idfc': 68 / 24,
    'idbi': 115 / 24,
    'csb': 81 / 24,
    'dcb': 98 / 24,
    'pnb': 122 / 24,
    'psb': 88 / 24,
    'deutsche': 123 / 24,
  };

  /// Wide logos that already carry their own opaque brand-coloured background,
  /// so they need no white plate behind them.
  static const Set<String> _selfBackedLogos = {'federal'};

  /// Wordmarks that remain transparent and adapt their text to the card while
  /// retaining the brand colours in the symbol.
  static const Set<String> _adaptiveWordmarks = {'icici'};

  final BankInfo? bank;
  final double size;
  final bool showFallback;
  final bool useSmall;
  final Color? backgroundColor;

  /// The foreground selected by the card contrast system. A light foreground
  /// indicates a dark card and takes precedence over [backgroundColor].
  final Color? foregroundColor;

  /// Upper bound for plated wordmarks, which are much wider than tall.
  final double? maxWidth;

  const BankLogo({
    super.key,
    required this.bank,
    this.size = 24,
    this.showFallback = true,
    this.useSmall = true,
    this.backgroundColor,
    this.foregroundColor,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (bank == null) {
      return showFallback ? _buildFallback(null) : const SizedBox.shrink();
    }

    final logoPath = useSmall
        ? (bank!.logoPathSmall ?? dummyLogoSmall)
        : (bank!.logoPathLarge ?? dummyLogoLarge);

    final isDarkBackground = foregroundColor != null
        ? foregroundColor!.computeLuminance() > 0.5
        : backgroundColor != null && backgroundColor!.computeLuminance() < 0.5;

    final bankId = bank!.id.toLowerCase();
    final aspectRatio = useSmall ? null : _wideLogoAspectRatios[bankId];

    if (aspectRatio != null) {
      final isAdaptive = _adaptiveWordmarks.contains(bankId);
      return _buildWideLogo(
        logoPath,
        aspectRatio,
        plated: !isAdaptive && !_selfBackedLogos.contains(bankId),
        colorMapper: isAdaptive
            ? _IciciWordmarkColorMapper(
                isDarkBackground ? Colors.white : Colors.black,
              )
            : null,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: SvgPicture.asset(
        logoPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        placeholderBuilder: (context) => _buildFallback(bank),
        errorBuilder: (context, error, stackTrace) => _buildFallback(bank),
        colorFilter: isDarkBackground
            ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
            : null,
      ),
    );
  }

  Widget _buildWideLogo(
    String logoPath,
    double aspectRatio, {
    required bool plated,
    ColorMapper? colorMapper,
  }) {
    final padding = plated ? size * 0.1 : 0.0;
    final availableWidth = (maxWidth ?? size * 4.5) - padding * 2;

    var logoHeight = size - padding * 2;
    var logoWidth = logoHeight * aspectRatio;
    if (logoWidth > availableWidth) {
      logoWidth = availableWidth;
      logoHeight = logoWidth / aspectRatio;
    }

    final logo = SvgPicture.asset(
      logoPath,
      width: logoWidth,
      height: logoHeight,
      fit: BoxFit.contain,
      colorMapper: colorMapper,
      placeholderBuilder: (context) => _buildFallback(bank),
      errorBuilder: (context, error, stackTrace) => _buildFallback(bank),
    );

    if (!plated) return logo;

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size / 5),
      ),
      child: logo,
    );
  }

  Widget _buildFallback(BankInfo? bankInfo) {
    final color = bankInfo?.primaryColor ?? Colors.grey;
    final short = bankInfo?.shortName ?? '?';
    final initials = short.length >= 2 ? short.substring(0, 2) : short;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size / 4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Center(
        child: Text(
          initials,
          style: AppTypography.style(
            fontSize: size * 0.4,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _IciciWordmarkColorMapper extends ColorMapper {
  static const _sourceTextColor = Color(0xFF004A7F);

  final Color textColor;

  const _IciciWordmarkColorMapper(this.textColor);

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    return color == _sourceTextColor ? textColor : color;
  }

  @override
  bool operator ==(Object other) =>
      other is _IciciWordmarkColorMapper && other.textColor == textColor;

  @override
  int get hashCode => textColor.hashCode;
}

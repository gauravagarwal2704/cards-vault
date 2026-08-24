import 'package:flutter/material.dart';

import '../models/app_icon_option.dart';

class AppIconArtwork extends StatelessWidget {
  const AppIconArtwork({
    super.key,
    required this.option,
    this.size,
    this.borderRadius = 22,
    this.addSurfaceShadow = false,
  });

  final AppIconOption option;
  final double? size;
  final double borderRadius;
  final bool addSurfaceShadow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final artwork = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.asset(
        option.assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    );

    if (!addSurfaceShadow) return artwork;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: artwork,
    );
  }
}

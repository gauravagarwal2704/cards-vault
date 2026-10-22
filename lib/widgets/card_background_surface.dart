import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/material.dart';

import '../data/card_designs.dart';
import '../models/card_image_placement.dart';
import 'card_custom_image.dart';
import 'card_background_reveal.dart';
import '../utils/card_contrast.dart';
import '../utils/image_utils.dart';

/// Shared renderer for built-in, custom-gradient, and image card backgrounds.
/// Using one surface keeps the add/edit previews and saved wallet cards in sync.
class CardBackgroundSurface extends StatelessWidget {
  final CardDesign? design;
  final Object? revealKey;
  final int? customGradientStartColor;
  final int? customGradientEndColor;
  final double customGradientAngle;
  final String? customBackgroundImagePath;
  final double backgroundImageBlur;
  final CardImagePlacement backgroundImagePlacement;
  final Color fallbackPrimaryColor;
  final Color fallbackSecondaryColor;
  final BorderRadius borderRadius;
  final Widget child;
  final bool showShadow;

  const CardBackgroundSurface({
    super.key,
    this.design,
    this.revealKey,
    this.customGradientStartColor,
    this.customGradientEndColor,
    this.customGradientAngle = 135,
    this.customBackgroundImagePath,
    this.backgroundImageBlur = 0,
    this.backgroundImagePlacement = const CardImagePlacement(),
    required this.fallbackPrimaryColor,
    required this.fallbackSecondaryColor,
    required this.borderRadius,
    required this.child,
    this.showShadow = true,
  });

  Color get primaryColor {
    if (customGradientStartColor != null) {
      return Color(customGradientStartColor!);
    }
    return design?.primaryColor ?? fallbackPrimaryColor;
  }

  Color get secondaryColor {
    if (customGradientEndColor != null) {
      return Color(customGradientEndColor!);
    }
    return design?.secondaryColor ?? fallbackSecondaryColor;
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = customBackgroundImagePath;
    final hasImage = imagePath != null && imagePath.isNotEmpty;
    final colors = <Color>[
      primaryColor,
      if (design?.accentColor != null && customGradientStartColor == null)
        design!.accentColor!,
      secondaryColor,
    ];
    final foreground =
        design?.foregroundColor ??
        (hasImage ? CardContrast.ivory : CardContrast.bestForeground(colors));
    final customGradientNeedsScrim =
        design == null &&
        !hasImage &&
        CardContrast.needsScrim(foreground, colors);
    final scrimOpacity = hasImage
        ? 0.32
        : design?.foregroundScrimOpacity ??
              (customGradientNeedsScrim ? 0.2 : 0);
    final scrimColor = foreground == CardContrast.charcoal
        ? CardContrast.ivory
        : const Color(0xFF111318);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: (hasImage ? Colors.black : primaryColor).withValues(
                    alpha: 0.28,
                  ),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cacheWidth = ImageUtils.cardDisplayCacheWidth(
              constraints.maxWidth,
              MediaQuery.devicePixelRatioOf(context),
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                if (revealKey != null)
                  CardBackgroundReveal(
                    backgroundKey: revealKey!,
                    imageProvider: !hasImage && design == null
                        ? null
                        : ResizeImage.resizeIfNeeded(
                            cacheWidth,
                            null,
                            hasImage
                                ? FileImage(File(imagePath))
                                : AssetImage(design!.assetPath),
                          ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: _backgroundLayers(
                        hasImage,
                        colors,
                        cacheWidth,
                        imagePath,
                        scrimOpacity,
                        scrimColor,
                      ),
                    ),
                  )
                else
                  ..._backgroundLayers(
                    hasImage,
                    colors,
                    cacheWidth,
                    imagePath,
                    scrimOpacity,
                    scrimColor,
                  ),
                child,
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _backgroundLayers(
    bool hasImage,
    List<Color> colors,
    int? cacheWidth,
    String? imagePath,
    double scrimOpacity,
    Color scrimColor,
  ) => [
    if (hasImage)
      const ColoredBox(color: Color(0xFF111318))
    else
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
            transform: GradientRotation(customGradientAngle * math.pi / 180),
          ),
        ),
      ),
    if (design != null && !hasImage)
      _buildImageLayer(
        Image.asset(
          design!.assetPath,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
          cacheWidth: cacheWidth,
        ),
        blur: design!.style == CardDesignStyle.image,
      ),
    if (hasImage)
      _buildImageLayer(
        CardCustomImage(
          path: imagePath!,
          placement: backgroundImagePlacement,
          cacheWidth: cacheWidth,
        ),
        blur: true,
      ),
    if (scrimOpacity > 0)
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scrimColor.withValues(alpha: scrimOpacity * 0.82),
              scrimColor.withValues(alpha: scrimOpacity * 0.18),
              scrimColor.withValues(alpha: scrimOpacity),
            ],
          ),
        ),
      ),
  ];

  Widget _buildImageLayer(Widget image, {required bool blur}) {
    final sigma = backgroundImageBlur.clamp(0.0, 12.0);
    if (!blur || sigma == 0) return image;

    return ImageFiltered(
      imageFilter: ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.mirror,
      ),
      child: image,
    );
  }
}

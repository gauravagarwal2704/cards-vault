import 'package:flutter/material.dart';

import '../utils/card_contrast.dart';

/// Categories mirror the supplied Figma frame names, with the original
/// Designer previews preserved as a separate Abstract collection.
enum CardDesignStyle {
  gradient,
  dualTone,
  abstract,
  designer,
  gradientBlur,
  glassmorphism,
  monochrome,
  image,
}

class CardDesign {
  final String id;
  final String name;
  final CardDesignStyle style;
  final String assetPath;
  final String? sourceSvgOverride;

  /// Fallback colors are also used for shadows and bank-logo contrast while
  /// the SVG is decoding.
  final Color primaryColor;
  final Color secondaryColor;
  final Color? accentColor;
  final Color foregroundColor;
  final double foregroundScrimOpacity;
  final bool hasPattern;
  final bool hasCircles;

  /// Exact extracted SVG retained as a design source. The app uses [assetPath]
  /// because Flutter intentionally ignores several of Figma's SVG filters.
  String get sourceSvgPath =>
      sourceSvgOverride ??
      assetPath
          .replaceFirst('assets/', 'design_sources/')
          .replaceFirst('.webp', '.svg');

  const CardDesign({
    required this.id,
    required this.name,
    required this.style,
    required this.assetPath,
    this.sourceSvgOverride,
    required this.primaryColor,
    required this.secondaryColor,
    this.accentColor,
    this.foregroundColor = CardContrast.ivory,
    this.foregroundScrimOpacity = 0,
    this.hasPattern = false,
    this.hasCircles = false,
  });
}

class CardDesigns {
  static List<CardDesign> _series({
    required CardDesignStyle style,
    required String idPrefix,
    required String frameName,
    required String assetDirectory,
    required int count,
    required Color primaryColor,
    required Color secondaryColor,
    Set<int> charcoalForeground = const {},
    Set<int> foregroundScrim = const {},
  }) {
    return List<CardDesign>.unmodifiable(
      List.generate(count, (index) {
        final number = (index + 1).toString().padLeft(2, '0');
        return CardDesign(
          id: '${idPrefix}_$number',
          name: '$frameName/$number',
          style: style,
          assetPath: 'assets/card_backgrounds/$assetDirectory/$number.webp',
          primaryColor: primaryColor,
          secondaryColor: secondaryColor,
          foregroundColor: charcoalForeground.contains(index + 1)
              ? CardContrast.charcoal
              : CardContrast.ivory,
          foregroundScrimOpacity: foregroundScrim.contains(index + 1)
              ? 0.24
              : 0,
        );
      }),
    );
  }

  static final List<CardDesign> gradient = _series(
    style: CardDesignStyle.gradient,
    idPrefix: 'gradient',
    frameName: 'Gradient',
    assetDirectory: 'gradient',
    count: 12,
    primaryColor: const Color(0xFF7C3AED),
    secondaryColor: const Color(0xFF2563EB),
    charcoalForeground: {2, 3, 4, 6, 9, 10, 12},
    foregroundScrim: {5, 6, 7, 8, 12},
  );

  static final List<CardDesign> dualTone = _series(
    style: CardDesignStyle.dualTone,
    idPrefix: 'dual_tone',
    frameName: 'Dual Tone',
    assetDirectory: 'dual_tone',
    count: 12,
    primaryColor: const Color(0xFF1E3A5F),
    secondaryColor: const Color(0xFFEA593A),
    charcoalForeground: {5, 6, 8},
    foregroundScrim: {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12},
  );

  /// The eight previously shipped Designer backgrounds remain available under
  /// their original IDs so existing cards keep the same appearance.
  static final List<CardDesign> abstract = _series(
    style: CardDesignStyle.abstract,
    idPrefix: 'designer',
    frameName: 'Abstract',
    assetDirectory: 'abstract',
    count: 8,
    primaryColor: const Color(0xFF8B3A86),
    secondaryColor: const Color(0xFFEA4C89),
    charcoalForeground: {2, 6, 8},
    foregroundScrim: {5},
  );

  static final List<CardDesign> designer = _series(
    style: CardDesignStyle.designer,
    idPrefix: 'designer_2',
    frameName: 'Designer 2.0',
    assetDirectory: 'designer_2',
    count: 18,
    primaryColor: const Color(0xFF8B3A86),
    secondaryColor: const Color(0xFFEA4C89),
    charcoalForeground: {2, 4, 8, 10, 12, 14, 16, 17},
    foregroundScrim: {1, 3, 13, 14, 15, 17, 18},
  );

  static final List<CardDesign> gradientBlur = _series(
    style: CardDesignStyle.gradientBlur,
    idPrefix: 'gradient_blur',
    frameName: 'Gradient Blur',
    assetDirectory: 'gradient_blur',
    count: 8,
    primaryColor: const Color(0xFF171717),
    secondaryColor: const Color(0xFF4C1D95),
    foregroundScrim: {1, 8},
  );

  static const List<CardDesign> glassmorphism = [
    CardDesign(
      id: 'glassmorphism_01',
      name: 'Glassmorphism/01',
      style: CardDesignStyle.glassmorphism,
      assetPath: 'assets/card_backgrounds/glassmorphism/01.webp',
      primaryColor: Color(0xFF4B4D52),
      secondaryColor: Color(0xFF1B1D21),
      foregroundColor: CardContrast.ivory,
      foregroundScrimOpacity: 0.16,
    ),
    CardDesign(
      id: 'glassmorphism_02',
      name: 'Glassmorphism/02',
      style: CardDesignStyle.glassmorphism,
      assetPath: 'assets/card_backgrounds/glassmorphism/02.webp',
      primaryColor: Color(0xFF24262B),
      secondaryColor: Color(0xFF0F1013),
      foregroundColor: CardContrast.ivory,
    ),
  ];

  static final List<CardDesign> monochrome = [
    const CardDesign(
      id: 'monochrome_01',
      name: 'Monochrome/01',
      style: CardDesignStyle.monochrome,
      // This frame is byte-identical to Abstract/08. Share the runtime raster
      // while retaining the original source path and stable saved-card ID.
      assetPath: 'assets/card_backgrounds/abstract/08.webp',
      sourceSvgOverride: 'design_sources/card_backgrounds/monochrome/01.svg',
      primaryColor: Colors.white,
      secondaryColor: Color(0xFFF2F2F2),
      foregroundColor: CardContrast.charcoal,
    ),
    const CardDesign(
      id: 'monochrome_02',
      name: 'Monochrome/02',
      style: CardDesignStyle.monochrome,
      assetPath: 'assets/card_backgrounds/monochrome/02.webp',
      primaryColor: Colors.black,
      secondaryColor: Color(0xFF111111),
    ),
  ];

  static final List<CardDesign> image = _series(
    style: CardDesignStyle.image,
    idPrefix: 'image',
    frameName: 'Image',
    assetDirectory: 'image',
    count: 6,
    primaryColor: const Color(0xFF334155),
    secondaryColor: const Color(0xFF0F172A),
    charcoalForeground: {2, 3, 4, 5},
    foregroundScrim: {1, 2, 3, 4, 5, 6},
  );

  static List<CardDesign> get all => List.unmodifiable([
    ...gradient,
    ...dualTone,
    ...abstract,
    ...designer,
    ...gradientBlur,
    ...glassmorphism,
    ...monochrome,
    ...image,
  ]);

  static final Map<String, String> _legacyAliases = {
    'hologram_silver': 'gradient_01',
    'hologram_gold': 'gradient_02',
    'hologram_rose': 'gradient_03',
    'hologram_platinum': 'gradient_04',
    'hologram_rainbow': 'gradient_05',
    'glass_frost': 'glassmorphism_01',
    'glass_dark': 'glassmorphism_02',
    'glass_ocean': 'gradient_blur_01',
    'glass_emerald': 'gradient_blur_02',
    'glass_amethyst': 'gradient_blur_03',
    'minimal_white': 'monochrome_01',
    'minimal_black': 'monochrome_02',
    'minimal_navy': 'dual_tone_01',
    'minimal_charcoal': 'dual_tone_03',
    'minimal_stone': 'dual_tone_04',
    'gradient_sunset': 'gradient_01',
    'gradient_ocean': 'gradient_02',
    'gradient_forest': 'gradient_03',
    'gradient_berry': 'gradient_04',
    'gradient_aurora': 'gradient_05',
    'gradient_ember': 'gradient_06',
    'gradient_midnight': 'gradient_07',
    'geometric_circles': 'designer_01',
    'geometric_green': 'designer_02',
    'geometric_blue': 'designer_03',
    'geometric_purple': 'designer_04',
    'geometric_red': 'designer_05',
    'geometric_yellow': 'designer_06',
    'geometric_pink': 'designer_07',
    'geometric_teal': 'designer_08',
    'designer_09': 'designer_2_01',
    'designer_10': 'designer_2_02',
    'designer_11': 'designer_2_03',
    'designer_12': 'designer_2_04',
    'designer_13': 'designer_2_05',
    'designer_14': 'designer_2_06',
    'designer_15': 'designer_2_07',
    'designer_16': 'designer_2_08',
    'designer_17': 'designer_2_09',
    'designer_18': 'designer_2_10',
    'designer_19': 'designer_2_11',
    'designer_20': 'designer_2_12',
    'designer_21': 'designer_2_13',
    'designer_22': 'designer_2_14',
    'designer_23': 'designer_2_15',
    'designer_24': 'designer_2_16',
    'designer_25': 'designer_2_17',
    'designer_26': 'designer_2_18',
  };

  static List<CardDesign> getByStyle(CardDesignStyle style) {
    return switch (style) {
      CardDesignStyle.gradient => gradient,
      CardDesignStyle.dualTone => dualTone,
      CardDesignStyle.abstract => abstract,
      CardDesignStyle.designer => designer,
      CardDesignStyle.gradientBlur => gradientBlur,
      CardDesignStyle.glassmorphism => glassmorphism,
      CardDesignStyle.monochrome => monochrome,
      CardDesignStyle.image => image,
    };
  }

  /// Returns the adjacent design in [style], wrapping at either end.
  /// A positive [direction] moves forward and a negative value moves back.
  static CardDesign cycle({
    required CardDesignStyle style,
    required String? currentId,
    required int direction,
  }) {
    final designs = getByStyle(style);
    assert(designs.isNotEmpty);

    final currentIndex = designs.indexWhere((design) => design.id == currentId);
    if (currentIndex == -1) {
      return direction < 0 ? designs.last : designs.first;
    }

    final nextIndex = (currentIndex + direction) % designs.length;
    return designs[nextIndex];
  }

  static CardDesign? getById(String id) {
    final resolvedId = _legacyAliases[id] ?? id;
    for (final design in all) {
      if (design.id == resolvedId) return design;
    }
    return null;
  }

  static String getStyleName(CardDesignStyle style) {
    return switch (style) {
      CardDesignStyle.gradient => 'Gradient',
      CardDesignStyle.dualTone => 'Dual Tone',
      CardDesignStyle.abstract => 'Abstract',
      CardDesignStyle.designer => 'Designer 2.0',
      CardDesignStyle.gradientBlur => 'Gradient Blur',
      CardDesignStyle.glassmorphism => 'Glassmorphism',
      CardDesignStyle.monochrome => 'Monochrome',
      CardDesignStyle.image => 'Image',
    };
  }
}

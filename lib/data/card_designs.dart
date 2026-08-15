import 'package:flutter/material.dart';

enum CardDesignStyle {
  hologram,
  glass,
  minimal,
  gradient,
  geometric,
}

class CardDesign {
  final String id;
  final String name;
  final CardDesignStyle style;
  final Color primaryColor;
  final Color secondaryColor;
  final Color? accentColor;
  final bool hasPattern;
  final bool hasCircles;

  const CardDesign({
    required this.id,
    required this.name,
    required this.style,
    required this.primaryColor,
    required this.secondaryColor,
    this.accentColor,
    this.hasPattern = false,
    this.hasCircles = false,
  });
}

class CardDesigns {
  // Hologram Designs - Iridescent/rainbow effects
  static const List<CardDesign> hologram = [
    CardDesign(
      id: 'hologram_silver',
      name: 'Silver Hologram',
      style: CardDesignStyle.hologram,
      primaryColor: Color(0xFFE8E8E8),
      secondaryColor: Color(0xFFB8B8B8),
      accentColor: Color(0xFFC0C0C0),
      hasPattern: true,
    ),
    CardDesign(
      id: 'hologram_gold',
      name: 'Gold Hologram',
      style: CardDesignStyle.hologram,
      primaryColor: Color(0xFFFFD700),
      secondaryColor: Color(0xFFDAA520),
      accentColor: Color(0xFFFFC107),
      hasPattern: true,
    ),
    CardDesign(
      id: 'hologram_rose',
      name: 'Rose Gold Hologram',
      style: CardDesignStyle.hologram,
      primaryColor: Color(0xFFE8B4B8),
      secondaryColor: Color(0xFFD4A5A5),
      accentColor: Color(0xFFF5D0D0),
      hasPattern: true,
    ),
    CardDesign(
      id: 'hologram_platinum',
      name: 'Platinum Hologram',
      style: CardDesignStyle.hologram,
      primaryColor: Color(0xFFE5E4E2),
      secondaryColor: Color(0xFFB0AFA8),
      accentColor: Color(0xFFC9C8C5),
      hasPattern: true,
    ),
    CardDesign(
      id: 'hologram_rainbow',
      name: 'Rainbow Hologram',
      style: CardDesignStyle.hologram,
      primaryColor: Color(0xFFE0E7FF),
      secondaryColor: Color(0xFFC7D2FE),
      accentColor: Color(0xFFA5B4FC),
      hasPattern: true,
    ),
  ];

  // Glass Designs - Frosted glass with blur
  static const List<CardDesign> glass = [
    CardDesign(
      id: 'glass_frost',
      name: 'Frosted Glass',
      style: CardDesignStyle.glass,
      primaryColor: Color(0xFFFFFFFF),
      secondaryColor: Color(0xFFF0F0F0),
      accentColor: Color(0xFF7C3AED),
    ),
    CardDesign(
      id: 'glass_dark',
      name: 'Dark Glass',
      style: CardDesignStyle.glass,
      primaryColor: Color(0xFF374151),
      secondaryColor: Color(0xFF1F2937),
      accentColor: Color(0xFF60A5FA),
    ),
    CardDesign(
      id: 'glass_ocean',
      name: 'Ocean Glass',
      style: CardDesignStyle.glass,
      primaryColor: Color(0xFF0EA5E9),
      secondaryColor: Color(0xFF0284C7),
      accentColor: Color(0xFF38BDF8),
    ),
    CardDesign(
      id: 'glass_emerald',
      name: 'Emerald Glass',
      style: CardDesignStyle.glass,
      primaryColor: Color(0xFF10B981),
      secondaryColor: Color(0xFF059669),
      accentColor: Color(0xFF34D399),
    ),
    CardDesign(
      id: 'glass_amethyst',
      name: 'Amethyst Glass',
      style: CardDesignStyle.glass,
      primaryColor: Color(0xFF8B5CF6),
      secondaryColor: Color(0xFF7C3AED),
      accentColor: Color(0xFFA78BFA),
    ),
  ];

  // Minimal Designs - Clean geometric patterns
  static const List<CardDesign> minimal = [
    CardDesign(
      id: 'minimal_white',
      name: 'Clean White',
      style: CardDesignStyle.minimal,
      primaryColor: Color(0xFFFAFAFA),
      secondaryColor: Color(0xFFF5F5F5),
      hasPattern: true,
    ),
    CardDesign(
      id: 'minimal_black',
      name: 'Matte Black',
      style: CardDesignStyle.minimal,
      primaryColor: Color(0xFF1A1A1A),
      secondaryColor: Color(0xFF0A0A0A),
      hasPattern: true,
    ),
    CardDesign(
      id: 'minimal_navy',
      name: 'Navy Blue',
      style: CardDesignStyle.minimal,
      primaryColor: Color(0xFF1E3A5F),
      secondaryColor: Color(0xFF152A45),
      hasPattern: true,
    ),
    CardDesign(
      id: 'minimal_charcoal',
      name: 'Charcoal',
      style: CardDesignStyle.minimal,
      primaryColor: Color(0xFF374151),
      secondaryColor: Color(0xFF1F2937),
      hasPattern: true,
    ),
    CardDesign(
      id: 'minimal_stone',
      name: 'Stone Grey',
      style: CardDesignStyle.minimal,
      primaryColor: Color(0xFF78716C),
      secondaryColor: Color(0xFF57534E),
      hasPattern: true,
    ),
  ];

  // Gradient Designs - Smooth color transitions
  static const List<CardDesign> gradient = [
    CardDesign(
      id: 'gradient_sunset',
      name: 'Sunset',
      style: CardDesignStyle.gradient,
      primaryColor: Color(0xFFF97316),
      secondaryColor: Color(0xFFEF4444),
      accentColor: Color(0xFFFBBF24),
    ),
    CardDesign(
      id: 'gradient_ocean',
      name: 'Deep Ocean',
      style: CardDesignStyle.gradient,
      primaryColor: Color(0xFF0EA5E9),
      secondaryColor: Color(0xFF6366F1),
      accentColor: Color(0xFF22D3EE),
    ),
    CardDesign(
      id: 'gradient_forest',
      name: 'Forest',
      style: CardDesignStyle.gradient,
      primaryColor: Color(0xFF22C55E),
      secondaryColor: Color(0xFF14B8A6),
      accentColor: Color(0xFF4ADE80),
    ),
    CardDesign(
      id: 'gradient_berry',
      name: 'Berry',
      style: CardDesignStyle.gradient,
      primaryColor: Color(0xFFEC4899),
      secondaryColor: Color(0xFF8B5CF6),
      accentColor: Color(0xFFF472B6),
    ),
    CardDesign(
      id: 'gradient_aurora',
      name: 'Aurora',
      style: CardDesignStyle.gradient,
      primaryColor: Color(0xFF06B6D4),
      secondaryColor: Color(0xFF8B5CF6),
      accentColor: Color(0xFF22D3EE),
    ),
    CardDesign(
      id: 'gradient_ember',
      name: 'Ember',
      style: CardDesignStyle.gradient,
      primaryColor: Color(0xFFDC2626),
      secondaryColor: Color(0xFF7C2D12),
      accentColor: Color(0xFFF87171),
    ),
    CardDesign(
      id: 'gradient_midnight',
      name: 'Midnight',
      style: CardDesignStyle.gradient,
      primaryColor: Color(0xFF312E81),
      secondaryColor: Color(0xFF1E1B4B),
      accentColor: Color(0xFF4338CA),
    ),
  ];

  // Geometric Designs - Shapes and circles
  static const List<CardDesign> geometric = [
    CardDesign(
      id: 'geometric_circles',
      name: 'Circles',
      style: CardDesignStyle.geometric,
      primaryColor: Color(0xFFD4D4D4),
      secondaryColor: Color(0xFFBDBDBD),
      accentColor: Color(0xFFE85D3F),
      hasCircles: true,
    ),
    CardDesign(
      id: 'geometric_green',
      name: 'Green Circles',
      style: CardDesignStyle.geometric,
      primaryColor: Color(0xFF7CB342),
      secondaryColor: Color(0xFF689F38),
      accentColor: Color(0xFF8BC34A),
      hasCircles: true,
    ),
    CardDesign(
      id: 'geometric_blue',
      name: 'Blue Waves',
      style: CardDesignStyle.geometric,
      primaryColor: Color(0xFF2196F3),
      secondaryColor: Color(0xFF1976D2),
      accentColor: Color(0xFF64B5F6),
      hasPattern: true,
    ),
    CardDesign(
      id: 'geometric_purple',
      name: 'Purple Shapes',
      style: CardDesignStyle.geometric,
      primaryColor: Color(0xFF9C27B0),
      secondaryColor: Color(0xFF7B1FA2),
      accentColor: Color(0xFFBA68C8),
      hasPattern: true,
    ),
    CardDesign(
      id: 'geometric_red',
      name: 'Red Geometric',
      style: CardDesignStyle.geometric,
      primaryColor: Color(0xFFE57373),
      secondaryColor: Color(0xFFEF5350),
      accentColor: Color(0xFFFF8A80),
      hasCircles: true,
    ),
    CardDesign(
      id: 'geometric_yellow',
      name: 'Yellow Minimal',
      style: CardDesignStyle.geometric,
      primaryColor: Color(0xFFFFF176),
      secondaryColor: Color(0xFFFFEE58),
      hasPattern: true,
    ),
    CardDesign(
      id: 'geometric_pink',
      name: 'Pink Blush',
      style: CardDesignStyle.geometric,
      primaryColor: Color(0xFFF8BBD9),
      secondaryColor: Color(0xFFF48FB1),
      accentColor: Color(0xFFF06292),
      hasCircles: true,
    ),
    CardDesign(
      id: 'geometric_teal',
      name: 'Teal Modern',
      style: CardDesignStyle.geometric,
      primaryColor: Color(0xFF26A69A),
      secondaryColor: Color(0xFF00897B),
      accentColor: Color(0xFF4DB6AC),
      hasPattern: true,
    ),
  ];

  static List<CardDesign> get all => [
    ...hologram,
    ...glass,
    ...minimal,
    ...gradient,
    ...geometric,
  ];

  static List<CardDesign> getByStyle(CardDesignStyle style) {
    switch (style) {
      case CardDesignStyle.hologram:
        return hologram;
      case CardDesignStyle.glass:
        return glass;
      case CardDesignStyle.minimal:
        return minimal;
      case CardDesignStyle.gradient:
        return gradient;
      case CardDesignStyle.geometric:
        return geometric;
    }
  }

  static CardDesign? getById(String id) {
    try {
      return all.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  static String getStyleName(CardDesignStyle style) {
    switch (style) {
      case CardDesignStyle.hologram:
        return 'Hologram';
      case CardDesignStyle.glass:
        return 'Glass';
      case CardDesignStyle.minimal:
        return 'Minimal';
      case CardDesignStyle.gradient:
        return 'Gradient';
      case CardDesignStyle.geometric:
        return 'Geometric';
    }
  }
}


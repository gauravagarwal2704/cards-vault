import 'package:flutter/material.dart';

enum AppBrightnessMode { system, light, dark, amoled }

enum AppColorSource { system, preset, custom }

enum AppPaletteStrategy {
  tonalSpot,
  expressive;

  DynamicSchemeVariant get schemeVariant => switch (this) {
    AppPaletteStrategy.tonalSpot => DynamicSchemeVariant.tonalSpot,
    AppPaletteStrategy.expressive => DynamicSchemeVariant.expressive,
  };

  String get label => switch (this) {
    AppPaletteStrategy.tonalSpot => 'Tonal spot',
    AppPaletteStrategy.expressive => 'Expressive',
  };

  String get description => switch (this) {
    AppPaletteStrategy.tonalSpot => 'Keeps your chosen color dominant',
    AppPaletteStrategy.expressive => 'Uses contrasting supporting colors',
  };
}

class AccentColorOption {
  final String id;
  final String name;
  final Color seedColor;

  const AccentColorOption({
    required this.id,
    required this.name,
    required this.seedColor,
  });

  static const AccentColorOption indigo = AccentColorOption(
    id: 'indigo',
    name: 'Indigo',
    seedColor: Color(0xFF6366F1),
  );

  static const AccentColorOption ocean = AccentColorOption(
    id: 'ocean',
    name: 'Ocean',
    seedColor: Color(0xFF0D9488),
  );

  static const AccentColorOption ember = AccentColorOption(
    id: 'ember',
    name: 'Ember',
    seedColor: Color(0xFFEA580C),
  );

  static const AccentColorOption forest = AccentColorOption(
    id: 'forest',
    name: 'Forest',
    seedColor: Color(0xFF16A34A),
  );

  static const AccentColorOption orchid = AccentColorOption(
    id: 'orchid',
    name: 'Orchid',
    seedColor: Color(0xFFDB2777),
  );

  static const AccentColorOption violet = AccentColorOption(
    id: 'violet',
    name: 'Violet',
    seedColor: Color(0xFF7C3AED),
  );

  static const AccentColorOption crimson = AccentColorOption(
    id: 'crimson',
    name: 'Crimson',
    seedColor: Color(0xFFDC2626),
  );

  static const AccentColorOption rose = AccentColorOption(
    id: 'rose',
    name: 'Rose',
    seedColor: Color(0xFFE11D48),
  );

  static const AccentColorOption amber = AccentColorOption(
    id: 'amber',
    name: 'Amber',
    seedColor: Color(0xFFF59E0B),
  );

  static const AccentColorOption yellow = AccentColorOption(
    id: 'yellow',
    name: 'Yellow',
    seedColor: Color(0xFFEAB308),
  );

  static const AccentColorOption graphite = AccentColorOption(
    id: 'graphite',
    name: 'Graphite',
    seedColor: Color(0xFF64748B),
  );

  static const List<AccentColorOption> presets = [
    indigo,
    ocean,
    ember,
    forest,
    orchid,
    violet,
    crimson,
    rose,
    amber,
    yellow,
    graphite,
  ];

  /// A deliberately compact set for the Appearance screen. The remaining
  /// presets stay available so existing saved preferences continue to load.
  static const List<AccentColorOption> featuredPresets = [
    indigo,
    ocean,
    ember,
    forest,
    orchid,
    graphite,
  ];

  static AccentColorOption? findById(String id) {
    for (final option in presets) {
      if (option.id == id) return option;
    }
    return null;
  }

  static AccentColorOption? findBySeed(Color color) {
    for (final option in presets) {
      if (option.seedColor.toARGB32() == color.toARGB32()) return option;
    }
    return null;
  }
}

/// Legacy combined theme ids kept for migrating saved preferences.
enum ThemeMode {
  light,
  dark,
  amoled,
  palette1,
  palette2,
  palette3,
  palette4,
  palette5,
}

class ThemeMigration {
  static (AppBrightnessMode, AccentColorOption) fromLegacy(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return (AppBrightnessMode.light, AccentColorOption.indigo);
      case ThemeMode.dark:
        return (AppBrightnessMode.dark, AccentColorOption.indigo);
      case ThemeMode.amoled:
        return (AppBrightnessMode.amoled, AccentColorOption.indigo);
      case ThemeMode.palette1:
        return (AppBrightnessMode.dark, AccentColorOption.ocean);
      case ThemeMode.palette2:
        return (AppBrightnessMode.dark, AccentColorOption.ember);
      case ThemeMode.palette3:
        return (AppBrightnessMode.dark, AccentColorOption.forest);
      case ThemeMode.palette4:
        return (AppBrightnessMode.dark, AccentColorOption.orchid);
      case ThemeMode.palette5:
        return (AppBrightnessMode.dark, AccentColorOption.graphite);
    }
  }
}

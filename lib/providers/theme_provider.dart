import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/theme_config.dart' as config;
import '../theme/app_theme.dart';

class ThemeProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const String _legacyThemeKey = 'selected_theme_mode';
  static const String _brightnessKey = 'appearance_brightness_mode';
  static const String _colorSourceKey = 'appearance_color_source';
  static const String _seedColorKey = 'appearance_seed_color';
  static const String _accentIdKey = 'appearance_accent_id';
  static const String _customColorKey = 'appearance_is_custom';
  static const String _paletteStrategyKey = 'appearance_palette_strategy';

  config.AppBrightnessMode _brightnessMode = config.AppBrightnessMode.system;
  config.AppColorSource _colorSource = config.AppColorSource.preset;
  config.AppPaletteStrategy _paletteStrategy =
      config.AppPaletteStrategy.expressive;
  Color _seedColor = config.AccentColorOption.indigo.seedColor;
  String? _accentId = config.AccentColorOption.indigo.id;
  Brightness _platformBrightness = Brightness.light;

  ThemeData _lightTheme = AppTheme.build(
    brightnessMode: config.AppBrightnessMode.light,
    seedColor: config.AccentColorOption.indigo.seedColor,
  );
  ThemeData _darkTheme = AppTheme.build(
    brightnessMode: config.AppBrightnessMode.dark,
    seedColor: config.AccentColorOption.indigo.seedColor,
  );
  ThemeData _oledTheme = AppTheme.build(
    brightnessMode: config.AppBrightnessMode.amoled,
    seedColor: config.AccentColorOption.indigo.seedColor,
  );

  ThemeProvider() {
    _platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    WidgetsBinding.instance.addObserver(this);
    _rebuildThemes();
    _loadTheme();
  }

  config.AppBrightnessMode get brightnessMode => _brightnessMode;
  config.AppBrightnessMode get currentMode => _brightnessMode;
  config.AppColorSource get colorSource => _colorSource;
  config.AppPaletteStrategy get paletteStrategy => _paletteStrategy;
  DynamicSchemeVariant get schemeVariant => _paletteStrategy.schemeVariant;
  Color get seedColor => _seedColor;
  String? get accentId => _accentId;
  bool get isCustomColor => _colorSource == config.AppColorSource.custom;
  bool get usesSystemColors => _colorSource == config.AppColorSource.system;

  ThemeData get lightTheme => _lightTheme;
  ThemeData get darkTheme => _darkTheme;
  ThemeData get oledTheme => _oledTheme;

  ThemeMode get materialThemeMode => switch (_brightnessMode) {
    config.AppBrightnessMode.system => ThemeMode.system,
    config.AppBrightnessMode.light => ThemeMode.light,
    config.AppBrightnessMode.dark ||
    config.AppBrightnessMode.amoled => ThemeMode.dark,
  };

  /// OLED mode supplies the black theme through MaterialApp's dark slot.
  ThemeData get materialDarkTheme => isAmoled ? _oledTheme : _darkTheme;

  ThemeData get currentTheme => switch (_brightnessMode) {
    config.AppBrightnessMode.light => _lightTheme,
    config.AppBrightnessMode.dark => _darkTheme,
    config.AppBrightnessMode.amoled => _oledTheme,
    config.AppBrightnessMode.system =>
      _platformBrightness == Brightness.dark ? _darkTheme : _lightTheme,
  };

  ColorScheme get colorScheme => currentTheme.colorScheme;
  bool get isDarkMode => colorScheme.brightness == Brightness.dark;
  bool get isAmoled => _brightnessMode == config.AppBrightnessMode.amoled;

  void _rebuildThemes() {
    final useSystemColors = _colorSource == config.AppColorSource.system;
    _lightTheme = AppTheme.build(
      brightnessMode: config.AppBrightnessMode.light,
      seedColor: _seedColor,
      schemeVariant: schemeVariant,
      useSystemColors: useSystemColors,
    );
    _darkTheme = AppTheme.build(
      brightnessMode: config.AppBrightnessMode.dark,
      seedColor: _seedColor,
      schemeVariant: schemeVariant,
      useSystemColors: useSystemColors,
    );
    _oledTheme = AppTheme.build(
      brightnessMode: config.AppBrightnessMode.amoled,
      seedColor: _seedColor,
      schemeVariant: schemeVariant,
      useSystemColors: useSystemColors,
    );
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final savedBrightness = prefs.getString(_brightnessKey);
      final savedSource = prefs.getString(_colorSourceKey);
      final savedSeed = prefs.getInt(_seedColorKey);
      final savedAccentId = prefs.getString(_accentIdKey);
      final savedCustom = prefs.getBool(_customColorKey);
      final savedPaletteStrategy = prefs.getString(_paletteStrategyKey);

      if (savedPaletteStrategy != null) {
        _paletteStrategy = config.AppPaletteStrategy.values.firstWhere(
          (strategy) => strategy.name == savedPaletteStrategy,
          orElse: () => config.AppPaletteStrategy.expressive,
        );
      }

      if (savedBrightness != null || savedSeed != null) {
        if (savedBrightness != null) {
          _brightnessMode = config.AppBrightnessMode.values.firstWhere(
            (mode) => mode.name == savedBrightness,
            orElse: () => config.AppBrightnessMode.system,
          );
        }
        if (savedSeed != null) _seedColor = Color(savedSeed);

        if (savedSource != null) {
          _colorSource = config.AppColorSource.values.firstWhere(
            (source) => source.name == savedSource,
            orElse: () => config.AppColorSource.preset,
          );
        } else if (savedCustom == true) {
          _colorSource = config.AppColorSource.custom;
        }

        _accentId = _colorSource == config.AppColorSource.custom
            ? null
            : (savedAccentId ??
                  config.AccentColorOption.findBySeed(_seedColor)?.id ??
                  config.AccentColorOption.indigo.id);
        if (_colorSource == config.AppColorSource.preset) {
          final preset = config.AccentColorOption.findById(_accentId!);
          if (preset != null) _seedColor = preset.seedColor;
        }
      } else {
        final legacy = prefs.getString(_legacyThemeKey);
        if (legacy != null) {
          final legacyMode = config.ThemeMode.values.firstWhere(
            (mode) => mode.name == legacy,
            orElse: () => config.ThemeMode.light,
          );
          final migrated = config.ThemeMigration.fromLegacy(legacyMode);
          _brightnessMode = migrated.$1;
          _seedColor = migrated.$2.seedColor;
          _accentId = migrated.$2.id;
          _colorSource = config.AppColorSource.preset;
          await _persist();
        }
      }

      _rebuildThemes();
      notifyListeners();
    } catch (error) {
      debugPrint('Error loading theme: $error');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_brightnessKey, _brightnessMode.name);
      await prefs.setString(_colorSourceKey, _colorSource.name);
      await prefs.setInt(_seedColorKey, _seedColor.toARGB32());
      await prefs.setBool(
        _customColorKey,
        _colorSource == config.AppColorSource.custom,
      );
      await prefs.setString(_paletteStrategyKey, _paletteStrategy.name);
      if (_accentId != null) {
        await prefs.setString(_accentIdKey, _accentId!);
      } else {
        await prefs.remove(_accentIdKey);
      }
    } catch (error) {
      debugPrint('Error saving theme: $error');
    }
  }

  Future<void> setBrightnessMode(config.AppBrightnessMode mode) async {
    if (_brightnessMode == mode) return;
    _brightnessMode = mode;
    await _persist();
    notifyListeners();
  }

  Future<void> setPaletteStrategy(config.AppPaletteStrategy strategy) async {
    if (_paletteStrategy == strategy) return;
    _paletteStrategy = strategy;
    _rebuildThemes();
    await _persist();
    notifyListeners();
  }

  Future<void> useSystemColorSource() async {
    if (_colorSource == config.AppColorSource.system) return;
    _colorSource = config.AppColorSource.system;
    _accentId ??= config.AccentColorOption.indigo.id;
    _rebuildThemes();
    await _persist();
    notifyListeners();
  }

  Future<void> setAccentColor(config.AccentColorOption option) async {
    _accentId = option.id;
    _seedColor = option.seedColor;
    _colorSource = config.AppColorSource.preset;
    _rebuildThemes();
    await _persist();
    notifyListeners();
  }

  Future<void> setCustomSeedColor(Color color) async {
    _seedColor = color;
    _accentId = null;
    _colorSource = config.AppColorSource.custom;
    _rebuildThemes();
    await _persist();
    notifyListeners();
  }

  @override
  void didChangePlatformBrightness() {
    final next = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    if (_platformBrightness == next) return;
    _platformBrightness = next;
    if (_brightnessMode == config.AppBrightnessMode.system) notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Color getBackgroundColor() => currentTheme.scaffoldBackgroundColor;
  Color getCardColor() => colorScheme.surfaceContainerHigh;
  Color getPrimaryTextColor() => colorScheme.onSurface;
  Color getSecondaryTextColor() => colorScheme.onSurfaceVariant;
  Color getPrimaryColor() => colorScheme.primary;
  Color getOnPrimaryColor() => colorScheme.onPrimary;
  Color getPrimaryContainerColor() => colorScheme.primaryContainer;
  Color getOnPrimaryContainerColor() => colorScheme.onPrimaryContainer;
  Color getSecondaryContainerColor() => colorScheme.secondaryContainer;
  Color getTertiaryColor() => colorScheme.tertiary;
  Color getOutlineColor() => colorScheme.outlineVariant;
}

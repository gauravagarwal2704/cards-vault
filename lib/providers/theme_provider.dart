import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/theme_config.dart' as config;
import '../theme/app_theme.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _legacyThemeKey = 'selected_theme_mode';
  static const String _brightnessKey = 'appearance_brightness_mode';
  static const String _seedColorKey = 'appearance_seed_color';
  static const String _accentIdKey = 'appearance_accent_id';
  static const String _customColorKey = 'appearance_is_custom';

  config.AppBrightnessMode _brightnessMode = config.AppBrightnessMode.light;
  Color _seedColor = config.AccentColorOption.indigo.seedColor;
  String? _accentId = config.AccentColorOption.indigo.id;
  bool _isCustomColor = false;
  ThemeData _currentTheme = AppTheme.build(
    brightnessMode: config.AppBrightnessMode.light,
    seedColor: config.AccentColorOption.indigo.seedColor,
  );

  ThemeProvider() {
    _loadTheme();
  }

  config.AppBrightnessMode get brightnessMode => _brightnessMode;
  /// Kept for callers that still check the old combined mode concept.
  config.AppBrightnessMode get currentMode => _brightnessMode;
  Color get seedColor => _seedColor;
  String? get accentId => _accentId;
  bool get isCustomColor => _isCustomColor;
  ThemeData get currentTheme => _currentTheme;
  ColorScheme get colorScheme => _currentTheme.colorScheme;
  bool get isDarkMode => colorScheme.brightness == Brightness.dark;
  bool get isAmoled => _brightnessMode == config.AppBrightnessMode.amoled;

  DynamicSchemeVariant get _schemeVariant {
    if (_isCustomColor) return DynamicSchemeVariant.tonalSpot;
    final preset = config.AccentColorOption.findById(_accentId ?? '');
    return preset?.schemeVariant ?? DynamicSchemeVariant.tonalSpot;
  }

  void _rebuildTheme() {
    _currentTheme = AppTheme.build(
      brightnessMode: _brightnessMode,
      seedColor: _seedColor,
      schemeVariant: _schemeVariant,
    );
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final savedBrightness = prefs.getString(_brightnessKey);
      final savedSeed = prefs.getInt(_seedColorKey);
      final savedAccentId = prefs.getString(_accentIdKey);
      final savedCustom = prefs.getBool(_customColorKey);

      if (savedBrightness != null || savedSeed != null) {
        if (savedBrightness != null) {
          _brightnessMode = config.AppBrightnessMode.values.firstWhere(
            (mode) => mode.name == savedBrightness,
            orElse: () => config.AppBrightnessMode.light,
          );
        }
        if (savedSeed != null) {
          _seedColor = Color(savedSeed);
        }
        _isCustomColor = savedCustom ?? false;
        _accentId = _isCustomColor
            ? null
            : (savedAccentId ??
                config.AccentColorOption.findBySeed(_seedColor)?.id ??
                config.AccentColorOption.indigo.id);
        if (!_isCustomColor) {
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
          _isCustomColor = false;
          await _persist();
        }
      }

      _rebuildTheme();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading theme: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_brightnessKey, _brightnessMode.name);
      await prefs.setInt(_seedColorKey, _seedColor.value);
      await prefs.setBool(_customColorKey, _isCustomColor);
      if (_accentId != null) {
        await prefs.setString(_accentIdKey, _accentId!);
      } else {
        await prefs.remove(_accentIdKey);
      }
    } catch (e) {
      debugPrint('Error saving theme: $e');
    }
  }

  Future<void> setBrightnessMode(config.AppBrightnessMode mode) async {
    if (_brightnessMode == mode) return;
    _brightnessMode = mode;
    _rebuildTheme();
    await _persist();
    notifyListeners();
  }

  Future<void> setAccentColor(config.AccentColorOption option) async {
    _accentId = option.id;
    _seedColor = option.seedColor;
    _isCustomColor = false;
    _rebuildTheme();
    await _persist();
    notifyListeners();
  }

  Future<void> setCustomSeedColor(Color color) async {
    _seedColor = color;
    _accentId = null;
    _isCustomColor = true;
    _rebuildTheme();
    await _persist();
    notifyListeners();
  }

  Color getBackgroundColor() => _currentTheme.scaffoldBackgroundColor;

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

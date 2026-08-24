import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_icon_option.dart';

class AppIconProvider extends ChangeNotifier {
  AppIconProvider() {
    _load();
  }

  static const _preferenceKey = 'appearance_app_icon';
  static const _channel = MethodChannel('cards_wallet/app_icon');

  AppIconOption _selected = AppIconCatalog.threeDimensional;
  bool _isInitialized = false;
  bool _isChanging = false;

  AppIconOption get selected => _selected;
  bool get isInitialized => _isInitialized;
  bool get isChanging => _isChanging;

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _selected = AppIconCatalog.findById(
        preferences.getString(_preferenceKey),
      );
    } catch (error) {
      debugPrint('Error loading app icon selection: $error');
    } finally {
      _isInitialized = true;
      notifyListeners();
      if (_supportsNativeIconChanges) {
        unawaited(_syncNativeIcon());
      }
    }
  }

  Future<void> _syncNativeIcon() async {
    try {
      await _channel.invokeMethod<bool>('setAppIcon', {'iconId': _selected.id});
    } on MissingPluginException {
      // Native icon switching is not available in Flutter widget tests.
    } on PlatformException catch (error) {
      debugPrint('Error synchronizing app icon: ${error.message}');
    }
  }

  Future<String?> selectIcon(AppIconOption option) async {
    if (_isChanging || option.id == _selected.id) return null;

    final previous = _selected;
    _selected = option;
    _isChanging = true;
    notifyListeners();

    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_preferenceKey, option.id);

      if (_supportsNativeIconChanges) {
        final changed = await _channel.invokeMethod<bool>('setAppIcon', {
          'iconId': option.id,
        });
        if (changed != true) {
          throw PlatformException(
            code: 'icon_change_failed',
            message: 'The device did not accept the icon change.',
          );
        }
      }

      return null;
    } on PlatformException catch (error) {
      _selected = previous;
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_preferenceKey, previous.id);
      return error.message ?? 'Could not change the app icon.';
    } catch (error) {
      _selected = previous;
      return 'Could not change the app icon.';
    } finally {
      _isChanging = false;
      notifyListeners();
    }
  }

  bool get _supportsNativeIconChanges =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
}

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the small amount of personalisation CardVault needs on the device.
class ProfileProvider extends ChangeNotifier {
  static const _displayNameKey = 'profile_display_name';

  String _displayName = '';
  bool _isInitialized = false;

  ProfileProvider() {
    _load();
  }

  String get displayName => _displayName;
  bool get isInitialized => _isInitialized;
  bool get hasCompletedOnboarding => _displayName.isNotEmpty;

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _displayName = preferences.getString(_displayNameKey)?.trim() ?? '';
    } catch (error) {
      debugPrint('Error loading profile: $error');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> setDisplayName(String value) async {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return;

    _displayName = normalized;
    notifyListeners();

    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_displayNameKey, normalized);
    } catch (error) {
      debugPrint('Error saving profile: $error');
    }
  }
}

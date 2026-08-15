import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';

class AppLockProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const String _appLockEnabledKey = 'app_lock_enabled';
  static const int _lockTimeoutSeconds = 30;

  bool _isAppLockEnabled = false;
  bool _isLocked = false;
  bool _isAuthenticating = false;
  DateTime? _lastBackgroundTime;
  final AuthService _authService = AuthService();

  AppLockProvider() {
    WidgetsBinding.instance.addObserver(this);
    _loadAppLockPreference();
  }

  bool get isAppLockEnabled => _isAppLockEnabled;
  bool get isLocked => _isLocked;
  bool get isAuthenticating => _isAuthenticating;

  Future<void> _loadAppLockPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isAppLockEnabled = prefs.getBool(_appLockEnabledKey) ?? false;
      if (_isAppLockEnabled) {
        _isLocked = true;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading app lock preference: $e');
    }
  }

  Future<void> setAppLockEnabled(bool enabled) async {
    _isAppLockEnabled = enabled;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_appLockEnabledKey, enabled);
    } catch (e) {
      debugPrint('Error saving app lock preference: $e');
    }

    if (enabled) {
      _isLocked = true;
      _authService.clearCardDetailsAuthCooldown();
    } else {
      _isLocked = false;
      _lastBackgroundTime = null;
    }

    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isAppLockEnabled) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _lastBackgroundTime = DateTime.now();
        break;
      case AppLifecycleState.resumed:
        if (_lastBackgroundTime != null) {
          final duration = DateTime.now().difference(_lastBackgroundTime!);
          if (duration.inSeconds >= _lockTimeoutSeconds) {
            _isLocked = true;
            _authService.clearCardDetailsAuthCooldown();
            notifyListeners();
          }
        }
        break;
      default:
        break;
    }
  }

  Future<bool> authenticate(BuildContext context) async {
    if (!_isLocked || _isAuthenticating) return true;

    _isAuthenticating = true;
    notifyListeners();

    try {
      final authenticated = await _authService.authenticateForAppLock(context);
      if (authenticated) {
        _isLocked = false;
        _lastBackgroundTime = null;
      }
      return authenticated;
    } finally {
      _isAuthenticating = false;
      notifyListeners();
    }
  }

  void unlock() {
    _isLocked = false;
    _lastBackgroundTime = null;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}


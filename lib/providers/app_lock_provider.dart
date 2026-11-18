import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/app_log_service.dart';

abstract interface class AppLockPreferenceStore {
  Future<bool> isEnabled();
  Future<void> setEnabled(bool enabled);
}

class SharedPreferencesAppLockPreferenceStore
    implements AppLockPreferenceStore {
  static const String _key = 'app_lock_enabled';
  static const bool defaultEnabled = true;

  @override
  Future<bool> isEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_key) ?? defaultEnabled;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key, enabled);
  }
}

class AppLockProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const Duration defaultLockTimeout = Duration(minutes: 2);

  bool _isAppLockEnabled = false;
  bool _isLocked = true;
  bool _isInitialized = false;
  bool _isAuthenticating = false;
  bool _isBackgrounded = false;
  DateTime? _backgroundedSince;
  int _authenticationEpoch = 0;
  final AppLockAuthenticator _authenticator;
  final AppLockPreferenceStore _preferenceStore;
  final Duration lockTimeout;
  final DateTime Function() _now;
  final bool observeLifecycle;
  final bool _useNativeLifecycle;
  final MethodChannel lifecycleChannel;

  AppLockProvider({
    AppLockAuthenticator? authenticator,
    AppLockPreferenceStore? preferenceStore,
    this.lockTimeout = defaultLockTimeout,
    DateTime Function()? now,
    this.observeLifecycle = true,
    bool? useNativeLifecycle,
    this.lifecycleChannel = const MethodChannel('cards_wallet/app_lifecycle'),
  }) : _authenticator = authenticator ?? AuthenticationCoordinator(),
       _preferenceStore =
           preferenceStore ?? SharedPreferencesAppLockPreferenceStore(),
       _now = now ?? DateTime.now,
       _useNativeLifecycle = useNativeLifecycle ?? Platform.isAndroid {
    if (observeLifecycle && _useNativeLifecycle) {
      lifecycleChannel.setMethodCallHandler((call) async {
        if (call.method == 'foregroundChanged') {
          _handleLifecycleState(
            call.arguments == true
                ? AppLifecycleState.resumed
                : AppLifecycleState.paused,
          );
        }
      });
    }
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  bool get isAppLockEnabled => _isAppLockEnabled;
  bool get isLocked => _isLocked;
  bool get isAuthenticating => _isAuthenticating;
  bool get isBackgrounded => _isBackgrounded;
  bool get isInitialized => _isInitialized;

  Future<void> _initialize() async {
    try {
      final enabled = _preferenceStore.isEnabled();
      await _authenticator.prepareForAppLock();
      _isAppLockEnabled = await enabled;
      _isLocked = _isAppLockEnabled;
    } catch (e, stackTrace) {
      AppLogService.instance.recordFailure(
        'Initialize app lock',
        e,
        stackTrace,
        category: 'Failure/Security',
      );
      // Startup security state is fail-closed. A transient storage/plugin
      // failure must not expose the wallet before the next successful launch.
      _isAppLockEnabled = true;
      _isLocked = true;
      debugPrint('Error initializing app lock: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> setAppLockEnabled(bool enabled) async {
    _isAppLockEnabled = enabled;

    try {
      await _preferenceStore.setEnabled(enabled);
    } catch (e, stackTrace) {
      AppLogService.instance.recordFailure(
        'Save app lock preference',
        e,
        stackTrace,
        category: 'Failure/Security',
      );
      debugPrint('Error saving app lock preference: $e');
    }

    if (enabled) {
      // Settings authenticates this change before calling us. Enabling the
      // preference must not invalidate that already-authenticated foreground
      // session; a subsequent app exit is subject to the normal cooldown.
      _authenticationEpoch++;
      _isLocked = false;
      _isBackgrounded = false;
      _backgroundedSince = null;
    } else {
      _authenticationEpoch++;
      if (_isAuthenticating) {
        unawaited(_authenticator.cancelAuthentication());
      }
      _isLocked = false;
      _isBackgrounded = false;
      _backgroundedSince = null;
    }

    AppLogService.instance.action(
      'Security',
      'App lock preference changed',
      details: {'enabled': enabled},
    );

    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Flutter's Android activity pauses while our native scanner remains
    // visible. Use application-wide activity visibility on Android instead.
    if (_useNativeLifecycle && state != AppLifecycleState.detached) return;
    _handleLifecycleState(state);
  }

  void _handleLifecycleState(AppLifecycleState state) {
    if (!_isAppLockEnabled) return;

    AppLogService.instance.action(
      'Lifecycle',
      'App lifecycle changed',
      details: {'state': state.name},
    );

    switch (state) {
      case AppLifecycleState.inactive:
        // Permission sheets and temporary focus loss are not an app exit.
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _isBackgrounded = true;
        _backgroundedSince ??= _now();
        if (!_isAuthenticating && _authenticator.isAuthenticationInProgress) {
          AppLogService.instance.action(
            'Security',
            'Lock deferred for device authentication overlay',
          );
          unawaited(AppLogService.instance.flush());
          break;
        }
        // Preserve an unlocked session during a short app exit. Only an
        // authentication still in flight must be invalidated immediately.
        if (_isAuthenticating || state == AppLifecycleState.detached) {
          _lockNow(cancelAuthentication: true);
        }
        unawaited(AppLogService.instance.flush());
        break;
      case AppLifecycleState.resumed:
        final wasBackgrounded = _isBackgrounded;
        final backgroundedSince = _backgroundedSince;
        _isBackgrounded = false;
        _backgroundedSince = null;
        if (backgroundedSince != null &&
            _now().difference(backgroundedSince) >= lockTimeout) {
          _lockNow(cancelAuthentication: true, notify: false);
        }
        // Pending widget launches must resume even within the unlock grace period.
        if (wasBackgrounded) notifyListeners();
        break;
    }
  }

  Future<bool> authenticate(BuildContext context) async {
    if (!_isLocked) return true;
    if (_isAuthenticating || _isBackgrounded) return false;

    final authenticationEpoch = ++_authenticationEpoch;
    _isAuthenticating = true;
    notifyListeners();

    try {
      final authenticated = await _authenticator.authenticateForAppLock(
        context,
      );
      if (authenticated &&
          authenticationEpoch == _authenticationEpoch &&
          _isAppLockEnabled &&
          !_isBackgrounded) {
        _isLocked = false;
        _backgroundedSince = null;
        AppLogService.instance.action('Security', 'Vault unlocked');
        return true;
      }
      return false;
    } catch (error, stackTrace) {
      AppLogService.instance.recordFailure(
        'Unlock vault',
        error,
        stackTrace,
        category: 'Failure/Security',
      );
      return false;
    } finally {
      _isAuthenticating = false;
      notifyListeners();
    }
  }

  void _lockNow({bool cancelAuthentication = false, bool notify = true}) {
    _authenticationEpoch++;
    if (cancelAuthentication &&
        (_isAuthenticating || _authenticator.isAuthenticationInProgress)) {
      unawaited(_authenticator.cancelAuthentication());
    }
    final changed = !_isLocked;
    _isLocked = true;
    _authenticator.clearCardDetailsAuthCooldown();
    if (changed) {
      AppLogService.instance.action('Security', 'Vault locked');
    }
    if (notify && changed) notifyListeners();
  }

  @override
  void dispose() {
    _authenticationEpoch++;
    if (_isAuthenticating) {
      unawaited(_authenticator.cancelAuthentication());
    }
    if (observeLifecycle && _useNativeLifecycle) {
      lifecycleChannel.setMethodCallHandler(null);
    }
    if (observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

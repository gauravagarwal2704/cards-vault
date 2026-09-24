import 'dart:async';

import 'package:flutter/material.dart';
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
  static const Duration defaultLockTimeout = Duration(seconds: 30);

  bool _isAppLockEnabled = false;
  bool _isLocked = true;
  bool _isInitialized = false;
  bool _isAuthenticating = false;
  bool _isBackgrounded = false;
  DateTime? _inactiveSince;
  int _authenticationEpoch = 0;
  final AppLockAuthenticator _authenticator;
  final AppLockPreferenceStore _preferenceStore;
  final Duration lockTimeout;
  final DateTime Function() _now;
  final bool observeLifecycle;

  AppLockProvider({
    AppLockAuthenticator? authenticator,
    AppLockPreferenceStore? preferenceStore,
    this.lockTimeout = defaultLockTimeout,
    DateTime Function()? now,
    this.observeLifecycle = true,
  }) : _authenticator = authenticator ?? AuthenticationCoordinator(),
       _preferenceStore =
           preferenceStore ?? SharedPreferencesAppLockPreferenceStore(),
       _now = now ?? DateTime.now {
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  bool get isAppLockEnabled => _isAppLockEnabled;
  bool get isLocked => _isLocked;
  bool get isAuthenticating => _isAuthenticating;
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
      // session; the next genuine background transition will lock the vault.
      _authenticationEpoch++;
      _isLocked = false;
      _isBackgrounded = false;
      _inactiveSince = null;
    } else {
      _authenticationEpoch++;
      if (_isAuthenticating) {
        unawaited(_authenticator.cancelAuthentication());
      }
      _isLocked = false;
      _isBackgrounded = false;
      _inactiveSince = null;
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
    if (!_isAppLockEnabled) return;

    AppLogService.instance.action(
      'Lifecycle',
      'App lifecycle changed',
      details: {'state': state.name},
    );

    switch (state) {
      case AppLifecycleState.inactive:
        // Local authentication and system permission sheets make the app
        // inactive. Give those short interruptions a bounded grace period,
        // but never let a real background transition keep the vault open.
        if (!_isAuthenticating) _inactiveSince ??= _now();
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _isBackgrounded = true;
        _inactiveSince ??= _now();
        if (!_isAuthenticating && _authenticator.isAuthenticationInProgress) {
          AppLogService.instance.action(
            'Security',
            'Lock deferred for device authentication overlay',
          );
          unawaited(AppLogService.instance.flush());
          break;
        }
        _lockNow(cancelAuthentication: true);
        unawaited(AppLogService.instance.flush());
        break;
      case AppLifecycleState.resumed:
        final inactiveSince = _inactiveSince;
        _isBackgrounded = false;
        _inactiveSince = null;
        if (inactiveSince != null &&
            _now().difference(inactiveSince) >= lockTimeout) {
          _lockNow(cancelAuthentication: true);
        }
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
        _inactiveSince = null;
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
    if (observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

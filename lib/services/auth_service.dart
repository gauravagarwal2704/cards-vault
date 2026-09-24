import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'app_log_service.dart';

abstract interface class AppLockAuthenticator {
  bool get isAuthenticationInProgress;
  Future<void> prepareForAppLock();
  Future<bool> authenticateForAppLock(BuildContext context);
  Future<void> cancelAuthentication();
  void clearCardDetailsAuthCooldown();
}

enum ProtectedAction {
  unlockApp,
  revealCardDetails,
  copyCardDetails,
  shareCardDetails,
  editCardDetails,
  exportVault,
  exportCard,
  manageProviderCredentials,
  viewSensitiveDiagnostics,
  changeSecuritySettings,
  testAuthentication;

  String get defaultReason => switch (this) {
    ProtectedAction.unlockApp => 'Unlock app to continue',
    ProtectedAction.revealCardDetails =>
      'Authenticate to reveal protected card details',
    ProtectedAction.copyCardDetails =>
      'Authenticate to copy protected card details',
    ProtectedAction.shareCardDetails =>
      'Authenticate to share protected card details',
    ProtectedAction.editCardDetails =>
      'Authenticate to edit protected card details',
    ProtectedAction.exportVault => 'Authenticate to export the vault',
    ProtectedAction.exportCard => 'Authenticate to export this card',
    ProtectedAction.manageProviderCredentials =>
      'Authenticate to change saved provider credentials',
    ProtectedAction.viewSensitiveDiagnostics =>
      'Authenticate to view sensitive diagnostics',
    ProtectedAction.changeSecuritySettings =>
      'Authenticate to change security settings',
    ProtectedAction.testAuthentication => 'Authenticate to test device access',
  };
}

abstract interface class AuthenticationBackend implements AppLockAuthenticator {
  String? get lastErrorMessage;
  Future<List<BiometricType>> getAvailableBiometrics();
  Future<bool> authenticateForProtectedAction({required String reason});
}

/// The only application-facing authentication policy entry point.
///
/// Callers identify the protected action; this coordinator owns the reason,
/// cooldown, device-authentication, cancellation, and app-unlock policy. The
/// platform backend is private so screens and services cannot bypass it.
class AuthenticationCoordinator implements AppLockAuthenticator {
  static final AuthenticationCoordinator _instance =
      AuthenticationCoordinator._(_LocalAuthenticationBackend());

  factory AuthenticationCoordinator() => _instance;

  @visibleForTesting
  AuthenticationCoordinator.forTesting(AuthenticationBackend backend)
    : _backend = backend;

  AuthenticationCoordinator._(this._backend);

  final AuthenticationBackend _backend;

  String? get lastErrorMessage => _backend.lastErrorMessage;

  @override
  bool get isAuthenticationInProgress => _backend.isAuthenticationInProgress;

  Future<bool> authorize(
    ProtectedAction action, {
    BuildContext? context,
    String? reason,
  }) async {
    final span = AppLogService.instance.startSpan(
      'Security',
      'Authentication',
      details: {'action': action.name},
    );
    try {
      late final bool authenticated;
      if (action == ProtectedAction.unlockApp) {
        if (context == null) {
          throw ArgumentError('App unlock authorization requires a context.');
        }
        authenticated = await authenticateForAppLock(context);
      } else {
        authenticated = await _backend.authenticateForProtectedAction(
          reason: reason ?? action.defaultReason,
        );
      }
      span.complete(details: {'action': action.name, 'success': authenticated});
      return authenticated;
    } catch (error, stackTrace) {
      span.fail(error, stackTrace);
      rethrow;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() =>
      _backend.getAvailableBiometrics();

  @override
  Future<void> prepareForAppLock() => _backend.prepareForAppLock();

  @override
  Future<bool> authenticateForAppLock(BuildContext context) =>
      _backend.authenticateForAppLock(context);

  @override
  Future<void> cancelAuthentication() => _backend.cancelAuthentication();

  @override
  void clearCardDetailsAuthCooldown() =>
      _backend.clearCardDetailsAuthCooldown();
}

class _LocalAuthenticationBackend implements AuthenticationBackend {
  static const Duration _cardDetailsCooldown = Duration(minutes: 5);

  final LocalAuthentication _localAuth = LocalAuthentication();
  String? _lastErrorMessage;
  DateTime? _cardDetailsAuthenticatedUntil;
  bool _isAuthenticationInProgress = false;

  @override
  String? get lastErrorMessage => _lastErrorMessage;

  @override
  bool get isAuthenticationInProgress => _isAuthenticationInProgress;

  bool get isCardDetailsAuthValid =>
      _cardDetailsAuthenticatedUntil != null &&
      DateTime.now().isBefore(_cardDetailsAuthenticatedUntil!);

  @override
  void clearCardDetailsAuthCooldown() {
    _cardDetailsAuthenticatedUntil = null;
  }

  void _markCardDetailsAuthenticated() {
    _cardDetailsAuthenticatedUntil = DateTime.now().add(_cardDetailsCooldown);
  }

  Future<bool> isBiometricAvailable() async {
    try {
      final bool canAuthenticateWithBiometrics =
          await _localAuth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();
      return canAuthenticate;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isDeviceAuthAvailable() async {
    try {
      return await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> prepareForAppLock() async {
    // LocalAuthentication availability is intentionally checked only when an
    // unlock is requested: some OEMs do not resolve that platform call until
    // the activity is resumed. Preparing local service state here keeps the
    // startup gate deterministic without weakening the later device check.
    _lastErrorMessage = null;
  }

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  Future<bool> authenticateWithBiometrics({String? reason}) async {
    _lastErrorMessage = null;
    _isAuthenticationInProgress = true;
    try {
      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason ?? 'Please authenticate to view card details',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      if (!didAuthenticate) {
        _lastErrorMessage = 'Authentication cancelled or failed';
      }
      return didAuthenticate;
    } on PlatformException catch (e) {
      _lastErrorMessage = e.message ?? 'Authentication unavailable';
      AppLogService.instance.action(
        'Security',
        'Device authentication platform failure',
        details: {'code': e.code},
      );
      debugPrint('Biometric authentication error: ${e.code} - ${e.message}');
      return false;
    } finally {
      _isAuthenticationInProgress = false;
    }
  }

  @override
  Future<bool> authenticateForAppLock(BuildContext context) async {
    final bool deviceSupported = await isDeviceAuthAvailable();

    if (deviceSupported) {
      try {
        final bool authenticated = await authenticateWithBiometrics(
          reason: 'Unlock app to continue',
        );
        if (authenticated) {
          // Unlocking the app counts as authenticating for card details, so the
          // user is not prompted twice within the same session.
          _markCardDetailsAuthenticated();
        }
        return authenticated;
      } catch (_) {
        return false;
      }
    }

    return false;
  }

  @override
  Future<void> cancelAuthentication() async {
    try {
      await _localAuth.stopAuthentication();
    } on PlatformException catch (e) {
      AppLogService.instance.action(
        'Security',
        'Authentication cancellation failed',
        details: {'code': e.code},
      );
      debugPrint('Could not cancel authentication: ${e.code} - ${e.message}');
    } catch (e) {
      AppLogService.instance.action(
        'Security',
        'Authentication cancellation failed',
        details: {'errorType': e.runtimeType},
      );
      debugPrint('Could not cancel authentication: $e');
    }
  }

  @override
  Future<bool> authenticateForProtectedAction({required String reason}) async {
    _lastErrorMessage = null;

    if (isCardDetailsAuthValid) {
      return true;
    }

    try {
      final bool deviceSupported = await _localAuth.isDeviceSupported();
      if (!deviceSupported) {
        _lastErrorMessage = 'Set up a device lock (PIN, pattern, or biometrics) to view sensitive details';
        return false;
      }

      _isAuthenticationInProgress = true;
      final bool authenticated;
      try {
        authenticated = await _localAuth.authenticate(
          localizedReason: reason,
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: false,
          ),
        );
      } finally {
        _isAuthenticationInProgress = false;
      }

      if (!authenticated) {
        _lastErrorMessage = 'Authentication cancelled or failed';
        return false;
      }

      _markCardDetailsAuthenticated();
      return true;
    } on PlatformException catch (e) {
      AppLogService.instance.action(
        'Security',
        'Protected authentication platform failure',
        details: {'code': e.code},
      );
      debugPrint('Biometric authentication error: ${e.code} - ${e.message}');
      switch (e.code) {
        case 'NotAvailable':
        case 'NotEnrolled':
        case 'PasscodeNotSet':
          _lastErrorMessage =
              'Set up a device lock (PIN, pattern, or biometrics) to continue';
          break;
        case 'LockedOut':
        case 'PermanentlyLockedOut':
          _lastErrorMessage = 'Too many attempts. Try again later.';
          break;
        default:
          _lastErrorMessage = e.message ?? 'Authentication failed';
      }
      return false;
    } catch (e) {
      AppLogService.instance.action(
        'Security',
        'Protected authentication failed',
        details: {'errorType': e.runtimeType},
      );
      debugPrint('Authentication error: $e');
      _lastErrorMessage = 'Authentication failed';
      return false;
    }
  }

  Future<bool> authenticateWithRetry(
    BuildContext context, {
    String? reason,
  }) async {
    final bool deviceSupported = await isDeviceAuthAvailable();

    if (!deviceSupported) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Set up a device lock (PIN, pattern, or biometrics) to continue',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return false;
    }

    bool authenticated = false;
    try {
      authenticated = await authenticateWithBiometrics(
        reason: reason ?? 'Authenticate to continue',
      );
    } on PlatformException catch (e) {
      debugPrint('Biometric error: ${e.code} - ${e.message}');
      if (context.mounted) {
        final retry = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Authentication Failed'),
            content: Text(
              e.message ?? 'Could not authenticate. Please try again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        );

        if (retry == true && context.mounted) {
          return authenticateWithRetry(context, reason: reason);
        }
      }
      return false;
    } catch (e) {
      debugPrint('Authentication error: $e');
      return false;
    }

    return authenticated;
  }
}

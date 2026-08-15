import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const Duration _cardDetailsCooldown = Duration(minutes: 5);

  final LocalAuthentication _localAuth = LocalAuthentication();
  String? _lastErrorMessage;
  DateTime? _cardDetailsAuthenticatedUntil;

  String? get lastErrorMessage => _lastErrorMessage;

  bool get isCardDetailsAuthValid =>
      _cardDetailsAuthenticatedUntil != null &&
      DateTime.now().isBefore(_cardDetailsAuthenticatedUntil!);

  void clearCardDetailsAuthCooldown() {
    _cardDetailsAuthenticatedUntil = null;
  }

  void _markCardDetailsAuthenticated() {
    _cardDetailsAuthenticatedUntil = DateTime.now().add(_cardDetailsCooldown);
  }

  Future<bool> isBiometricAvailable() async {
    try {
      final bool canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
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

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  Future<bool> authenticateWithBiometrics({String? reason}) async {
    _lastErrorMessage = null;
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
      debugPrint('Biometric authentication error: ${e.code} - ${e.message}');
      return false;
    }
  }

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

  Future<bool> authenticateForCardDetails({String? reason}) async {
    _lastErrorMessage = null;

    if (isCardDetailsAuthValid) {
      return true;
    }

    try {
      final bool deviceSupported = await _localAuth.isDeviceSupported();
      if (!deviceSupported) {
        _lastErrorMessage =
            'Set up a device lock (PIN, pattern, or biometrics) to view sensitive details';
        return false;
      }

      final bool authenticated = await _localAuth.authenticate(
        localizedReason: reason ?? 'Authenticate to view card details',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

      if (!authenticated) {
        _lastErrorMessage = 'Authentication cancelled or failed';
        return false;
      }

      _markCardDetailsAuthenticated();
      return true;
    } on PlatformException catch (e) {
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
      debugPrint('Authentication error: $e');
      _lastErrorMessage = 'Authentication failed';
      return false;
    }
  }

  Future<bool> authenticateWithRetry(BuildContext context, {String? reason}) async {
    final bool deviceSupported = await isDeviceAuthAvailable();

    if (!deviceSupported) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Set up a device lock (PIN, pattern, or biometrics) to continue',
            ),
            backgroundColor: Colors.red,
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

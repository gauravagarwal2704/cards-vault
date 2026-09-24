import 'dart:io';

import 'package:cards_wallet/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

class _FakeAuthenticationBackend implements AuthenticationBackend {
  @override
  bool isAuthenticationInProgress = false;
  bool protectedResult = true;
  bool appLockResult = true;
  String? receivedReason;
  int protectedCalls = 0;
  int appLockCalls = 0;
  int cancelCalls = 0;
  int clearCooldownCalls = 0;
  int prepareCalls = 0;

  @override
  String? lastErrorMessage;

  @override
  Future<bool> authenticateForProtectedAction({required String reason}) async {
    protectedCalls++;
    receivedReason = reason;
    return protectedResult;
  }

  @override
  Future<bool> authenticateForAppLock(BuildContext context) async {
    appLockCalls++;
    return appLockResult;
  }

  @override
  Future<void> cancelAuthentication() async {
    cancelCalls++;
  }

  @override
  void clearCardDetailsAuthCooldown() {
    clearCooldownCalls++;
  }

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => const [
    BiometricType.fingerprint,
  ];

  @override
  Future<void> prepareForAppLock() async {
    prepareCalls++;
  }
}

void main() {
  test('every protected action has an explicit authentication reason', () {
    for (final action in ProtectedAction.values) {
      expect(
        action.defaultReason.trim(),
        isNotEmpty,
        reason: '${action.name} must explain its device-authentication prompt',
      );
    }
  });

  test('protected decisions use the centralized backend policy', () async {
    final backend = _FakeAuthenticationBackend();
    final coordinator = AuthenticationCoordinator.forTesting(backend);

    for (final action in ProtectedAction.values.where(
      (action) => action != ProtectedAction.unlockApp,
    )) {
      expect(await coordinator.authorize(action), isTrue);
      expect(backend.receivedReason, action.defaultReason);
    }

    expect(backend.protectedCalls, ProtectedAction.values.length - 1);
    expect(
      await coordinator.authorize(
        ProtectedAction.exportVault,
        reason: 'Custom export reason',
      ),
      isTrue,
    );
    expect(backend.receivedReason, 'Custom export reason');
  });

  testWidgets('app unlock is routed to the app-lock policy', (tester) async {
    final backend = _FakeAuthenticationBackend();
    final coordinator = AuthenticationCoordinator.forTesting(backend);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(
      await coordinator.authorize(ProtectedAction.unlockApp, context: context),
      isTrue,
    );
    expect(backend.appLockCalls, 1);
    expect(backend.protectedCalls, 0);
  });

  test('app unlock cannot run without a widget context', () {
    final coordinator = AuthenticationCoordinator.forTesting(
      _FakeAuthenticationBackend(),
    );

    expect(
      () => coordinator.authorize(ProtectedAction.unlockApp),
      throwsArgumentError,
    );
  });

  test('sensitive screens declare their protected action boundaries', () {
    final filesToActions = <String, List<String>>{
      'lib/screens/card_detail_screen.dart': [
        'ProtectedAction.revealCardDetails',
        'ProtectedAction.copyCardDetails',
        'ProtectedAction.shareCardDetails',
        'ProtectedAction.exportCard',
        'ProtectedAction.editCardDetails',
      ],
      'lib/screens/settings_screen.dart': [
        'ProtectedAction.exportVault',
        'ProtectedAction.changeSecuritySettings',
      ],
      'lib/screens/ai_scan_settings_screen.dart': [
        'ProtectedAction.manageProviderCredentials',
        'ProtectedAction.viewSensitiveDiagnostics',
        'ProtectedAction.changeSecuritySettings',
      ],
      'lib/screens/developer_options_screen.dart': [
        'ProtectedAction.testAuthentication',
      ],
    };

    for (final entry in filesToActions.entries) {
      final source = File(entry.key).readAsStringSync();
      for (final action in entry.value) {
        expect(
          source,
          contains(action),
          reason: '${entry.key} must route $action through the coordinator',
        );
      }
    }

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      expect(source, isNot(contains('AuthService(')), reason: entity.path);
      expect(
        source,
        isNot(contains('authenticateForCardDetails')),
        reason: entity.path,
      );
    }
  });
}

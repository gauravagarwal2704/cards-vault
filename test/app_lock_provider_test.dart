import 'dart:async';

import 'package:cards_wallet/providers/app_lock_provider.dart';
import 'package:cards_wallet/main.dart';
import 'package:cards_wallet/screens/saved_cards_screen.dart';
import 'package:cards_wallet/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAppLockAuthenticator implements AppLockAuthenticator {
  bool nextResult = true;
  @override
  bool isAuthenticationInProgress = false;
  Completer<bool>? pendingAuthentication;
  int authenticationCalls = 0;
  int cancellationCalls = 0;
  int clearCooldownCalls = 0;
  Completer<void>? pendingPreparation;

  @override
  Future<void> prepareForAppLock() {
    return pendingPreparation?.future ?? Future.value();
  }

  @override
  Future<bool> authenticateForAppLock(BuildContext context) {
    authenticationCalls++;
    return pendingAuthentication?.future ?? Future.value(nextResult);
  }

  @override
  Future<void> cancelAuthentication() async {
    cancellationCalls++;
  }

  @override
  void clearCardDetailsAuthCooldown() {
    clearCooldownCalls++;
  }
}

class _ControlledAppLockPreferenceStore implements AppLockPreferenceStore {
  final Completer<bool> read = Completer<bool>();
  bool? savedValue;

  @override
  Future<bool> isEnabled() => read.future;

  @override
  Future<void> setEnabled(bool enabled) async {
    savedValue = enabled;
  }
}

Future<BuildContext> _mountContext(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (builderContext) {
          context = builderContext;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pump();
  return context;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'app_lock_enabled': true});
  });

  test('app lock is enabled by default when no preference exists', () async {
    SharedPreferences.setMockInitialValues({});

    final store = SharedPreferencesAppLockPreferenceStore();

    expect(await store.isEnabled(), isTrue);
  });

  test('an explicitly disabled app lock remains disabled', () async {
    SharedPreferences.setMockInitialValues({'app_lock_enabled': false});

    final store = SharedPreferencesAppLockPreferenceStore();

    expect(await store.isEnabled(), isFalse);
  });

  testWidgets('a paused app locks the vault immediately', (tester) async {
    final authenticator = _FakeAppLockAuthenticator();
    final provider = AppLockProvider(
      authenticator: authenticator,
      observeLifecycle: false,
    );
    addTearDown(provider.dispose);
    final context = await _mountContext(tester);

    expect(provider.isLocked, isTrue);
    expect(await provider.authenticate(context), isTrue);
    expect(provider.isLocked, isFalse);

    provider.didChangeAppLifecycleState(AppLifecycleState.paused);

    expect(provider.isLocked, isTrue);
    expect(authenticator.clearCooldownCalls, 1);
  });

  testWidgets('enabling app lock keeps the authenticated session open', (
    tester,
  ) async {
    final authenticator = _FakeAppLockAuthenticator();
    final preferences = _ControlledAppLockPreferenceStore()
      ..read.complete(false);
    final provider = AppLockProvider(
      authenticator: authenticator,
      preferenceStore: preferences,
      observeLifecycle: false,
    );
    addTearDown(provider.dispose);
    await tester.pump();

    await provider.setAppLockEnabled(true);

    expect(provider.isAppLockEnabled, isTrue);
    expect(provider.isLocked, isFalse);
    expect(preferences.savedValue, isTrue);

    provider.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(provider.isLocked, isTrue);
  });

  testWidgets('short protected-auth overlay does not lock the vault', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 6, 12);
    final authenticator = _FakeAppLockAuthenticator();
    final provider = AppLockProvider(
      authenticator: authenticator,
      lockTimeout: const Duration(seconds: 30),
      now: () => now,
      observeLifecycle: false,
    );
    addTearDown(provider.dispose);
    final context = await _mountContext(tester);
    expect(await provider.authenticate(context), isTrue);

    authenticator.isAuthenticationInProgress = true;
    provider.didChangeAppLifecycleState(AppLifecycleState.inactive);
    provider.didChangeAppLifecycleState(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 2));
    provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
    authenticator.isAuthenticationInProgress = false;

    expect(provider.isLocked, isFalse);
  });

  testWidgets('long protected-auth overlay locks and cancels authentication', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 6, 12);
    final authenticator = _FakeAppLockAuthenticator();
    final provider = AppLockProvider(
      authenticator: authenticator,
      lockTimeout: const Duration(seconds: 30),
      now: () => now,
      observeLifecycle: false,
    );
    addTearDown(provider.dispose);
    final context = await _mountContext(tester);
    expect(await provider.authenticate(context), isTrue);

    authenticator.isAuthenticationInProgress = true;
    provider.didChangeAppLifecycleState(AppLifecycleState.inactive);
    provider.didChangeAppLifecycleState(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 30));
    provider.didChangeAppLifecycleState(AppLifecycleState.resumed);

    expect(provider.isLocked, isTrue);
    expect(authenticator.cancellationCalls, 1);
  });

  testWidgets('inactive grace period locks only after the configured timeout', (
    tester,
  ) async {
    var now = DateTime(2026, 8, 26, 12);
    final authenticator = _FakeAppLockAuthenticator();
    final provider = AppLockProvider(
      authenticator: authenticator,
      lockTimeout: const Duration(seconds: 10),
      now: () => now,
      observeLifecycle: false,
    );
    addTearDown(provider.dispose);
    final context = await _mountContext(tester);
    expect(await provider.authenticate(context), isTrue);

    provider.didChangeAppLifecycleState(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 9));
    provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(provider.isLocked, isFalse);

    provider.didChangeAppLifecycleState(AppLifecycleState.inactive);
    now = now.add(const Duration(seconds: 10));
    provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(provider.isLocked, isTrue);
  });

  testWidgets('backgrounding invalidates an in-flight authentication', (
    tester,
  ) async {
    final authenticator = _FakeAppLockAuthenticator()
      ..pendingAuthentication = Completer<bool>();
    final provider = AppLockProvider(
      authenticator: authenticator,
      observeLifecycle: false,
    );
    addTearDown(provider.dispose);
    final context = await _mountContext(tester);

    final authentication = provider.authenticate(context);
    await tester.pump();
    expect(provider.isAuthenticating, isTrue);

    provider.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(provider.isLocked, isTrue);
    expect(authenticator.cancellationCalls, 1);

    authenticator.pendingAuthentication!.complete(true);
    expect(await authentication, isFalse);
    expect(provider.isLocked, isTrue);
    expect(provider.isAuthenticating, isFalse);
  });

  testWidgets('cancelled authentication never unlocks the vault', (
    tester,
  ) async {
    final authenticator = _FakeAppLockAuthenticator()..nextResult = false;
    final provider = AppLockProvider(
      authenticator: authenticator,
      observeLifecycle: false,
    );
    addTearDown(provider.dispose);
    final context = await _mountContext(tester);

    expect(await provider.authenticate(context), isFalse);
    expect(provider.isLocked, isTrue);
    expect(provider.isAuthenticating, isFalse);
    expect(authenticator.authenticationCalls, 1);
  });

  testWidgets(
    'initialization remains fail-closed until preference and auth are ready',
    (tester) async {
      final preferences = _ControlledAppLockPreferenceStore();
      final authenticator = _FakeAppLockAuthenticator()
        ..pendingPreparation = Completer<void>();
      final provider = AppLockProvider(
        authenticator: authenticator,
        preferenceStore: preferences,
        observeLifecycle: false,
      );
      addTearDown(provider.dispose);

      expect(provider.isInitialized, isFalse);
      expect(provider.isLocked, isTrue);

      preferences.read.complete(false);
      await tester.pump();
      expect(provider.isInitialized, isFalse);
      expect(provider.isLocked, isTrue);

      authenticator.pendingPreparation!.complete();
      await tester.pump();
      expect(provider.isInitialized, isTrue);
      expect(provider.isLocked, isFalse);
    },
  );

  testWidgets('protected home is absent until startup gates and unlock pass', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'profile_display_name': 'Avery'});
    final preferences = _ControlledAppLockPreferenceStore();
    final authenticator = _FakeAppLockAuthenticator()
      ..pendingAuthentication = Completer<bool>();
    final provider = AppLockProvider(
      authenticator: authenticator,
      preferenceStore: preferences,
      observeLifecycle: false,
    );
    final securityInitialization = Completer<void>();

    await tester.pumpWidget(
      MyApp(
        appLockProviderFactory: () => provider,
        securityInitializer: () => securityInitialization.future,
      ),
    );
    expect(find.byKey(const ValueKey('initializing')), findsOneWidget);
    expect(find.byType(SavedCardsScreen), findsNothing);

    preferences.read.complete(true);
    await tester.pump();
    expect(provider.isInitialized, isTrue);
    expect(find.byKey(const ValueKey('initializing')), findsOneWidget);
    expect(find.byType(SavedCardsScreen), findsNothing);

    securityInitialization.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('CardVault is locked'), findsOneWidget);
    expect(find.byType(SavedCardsScreen), findsNothing);

    authenticator.pendingAuthentication!.complete(true);
    await tester.pump();
    expect(find.byType(SavedCardsScreen), findsOneWidget);
  });
}

import 'dart:async';

import 'package:cards_wallet/main.dart';
import 'package:cards_wallet/models/card_data.dart';
import 'package:cards_wallet/services/secure_card_storage.dart';
import 'package:cards_wallet/screens/card_detail_screen.dart';
import 'package:cards_wallet/providers/app_lock_provider.dart';
import 'package:cards_wallet/services/auth_service.dart';
import 'package:cards_wallet/services/home_widget_service.dart';
import 'package:cards_wallet/screens/home_widget_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

void main() {
  testWidgets('widget editor keeps Save in the app bar without switches', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(HomeWidgetService.channel, (call) async {
      if (call.method == 'configuration') return {'ids': <String>[]};
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(HomeWidgetService.channel, null),
    );
    await tester.pumpWidget(
      const MaterialApp(home: HomeWidgetSettingsScreen(widgetId: 7, cards: [])),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Save')),
      findsOneWidget,
    );
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets(
    'widget configuration waits for unlock and stays protected on relock',
    (tester) async {
      SharedPreferences.setMockInitialValues({'profile_display_name': 'Avery'});
      FlutterSecureStorage.setMockInitialValues({'saved_cards_list': '[]'});
      var now = DateTime(2026, 10, 28);
      final authenticator = _FakeAppLockAuthenticator()
        ..pendingAuthentication = Completer<bool>();
      final provider = AppLockProvider(
        authenticator: authenticator,
        observeLifecycle: false,
        useNativeLifecycle: false,
        now: () => now,
      );
      final service = HomeWidgetService.instance;
      service.pending.value = const WidgetLaunch(widgetId: 42);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(HomeWidgetService.channel, (
        call,
      ) async {
        if (call.method == 'configuration') {
          return {'ids': <String>[], 'showDetails': false};
        }
        return null;
      });
      addTearDown(() {
        service.pending.value = null;
        messenger.setMockMethodCallHandler(HomeWidgetService.channel, null);
      });
      await tester.pumpWidget(
        MyApp(
          appLockProviderFactory: () => provider,
          securityInitializer: () async {},
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.text('CardVault is locked'), findsOneWidget);
      expect(find.byType(HomeWidgetSettingsScreen), findsNothing);
      expect(service.pending.value?.widgetId, 42);

      authenticator.pendingAuthentication!.complete(true);
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(HomeWidgetSettingsScreen), findsOneWidget);
      expect(service.pending.value, isNull);
      final settingsState = tester.state(find.byType(HomeWidgetSettingsScreen));

      // Warm taps must replace the destination without waiting for Back.
      service.pending.value = const WidgetLaunch(widgetId: 43);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<HomeWidgetSettingsScreen>(
              find.byType(HomeWidgetSettingsScreen),
            )
            .widgetId,
        43,
      );
      final warmSettingsState = tester.state(
        find.byType(HomeWidgetSettingsScreen),
      );
      expect(warmSettingsState, isNot(same(settingsState)));

      authenticator.pendingAuthentication = Completer<bool>();
      provider.didChangeAppLifecycleState(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 3));
      provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(HomeWidgetSettingsScreen), findsNothing);
      expect(find.text('CardVault is locked'), findsOneWidget);
      expect(
        tester.state(
          find.byType(HomeWidgetSettingsScreen, skipOffstage: false),
        ),
        same(warmSettingsState),
      );
      authenticator.pendingAuthentication!.complete(true);
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(HomeWidgetSettingsScreen)),
        same(warmSettingsState),
      );
      // Resolve each card from current storage, independent of wallet ordering.
      final storage = SecureCardStorage();
      for (final id in ['card-a', 'card-b']) {
        await storage.saveCard(
          await CardData.fromPlaintext(
            id: id,
            cardNumber: '4111111111111111',
            expiryDate: '12/30',
            cardType: 'Visa',
            cardNickname: id,
          ),
        );
      }
      for (final id in ['card-a', 'card-b']) {
        service.pending.value = WidgetLaunch(cardId: id);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CardDetailScreen>(find.byType(CardDetailScreen))
              .card
              .id,
          id,
        );
      }
      service.pending.value = const WidgetLaunch(cardId: 'removed-card');
      await tester.pumpAndSettle();
      expect(find.byType(CardDetailScreen), findsNothing);
      expect(
        find.text('This card is no longer in your wallet.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

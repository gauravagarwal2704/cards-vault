import 'package:cards_wallet/models/card_data.dart';
import 'package:cards_wallet/providers/theme_provider.dart';
import 'package:cards_wallet/screens/card_detail_screen.dart';
import 'package:cards_wallet/screens/card_edit_screen.dart';
import 'package:cards_wallet/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DetailTestCard extends CardData {
  _DetailTestCard()
    : super(
        encryptedCardNumber: 'unused',
        encryptedExpiryDate: 'unused',
        lastFourDigits: '1111',
        cardType: 'Visa',
        cardNickname: 'Everyday',
      );

  @override
  Future<String> getDecryptedCardNumber() async => '4111111111111111';

  @override
  Future<String> getDecryptedExpiryDate() async => '12/30';

  @override
  Future<String?> getDecryptedCardholderName() async => 'Test User';

  @override
  Future<String?> getDecryptedCvv() async => '123';

  @override
  Future<String?> getDecryptedAccountNumber() async => null;

  @override
  Future<String?> getDecryptedIfscCode() async => null;

  @override
  Future<String?> getDecryptedUpiId() async => null;
}

Widget _testApp() {
  return MultiProvider(
    providers: [
      Provider<AuthenticationCoordinator>.value(
        value: AuthenticationCoordinator.forTesting(_AllowAuthentication()),
      ),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
    ],
    child: Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) => MaterialApp(
        theme: themeProvider.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        CardDetailScreen(card: _DetailTestCard(), cardIndex: 0),
                  ),
                ),
                child: const Text('Open card'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _AllowAuthentication implements AuthenticationBackend {
  @override
  bool isAuthenticationInProgress = false;
  @override
  String? get lastErrorMessage => null;

  @override
  Future<bool> authenticateForProtectedAction({required String reason}) async =>
      true;

  @override
  Future<bool> authenticateForAppLock(BuildContext context) async => true;

  @override
  Future<void> cancelAuthentication() async {}

  @override
  void clearCardDetailsAuthCooldown() {}

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => const [];

  @override
  Future<void> prepareForAppLock() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('detail sections expose full-card edit actions', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.tap(find.text('Open card'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('edit-card-details')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('edit-additional-information')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('edit-card-details')),
        matching: find.byIcon(Icons.edit_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('dragging the displayed card down closes its detail route', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.tap(find.text('Open card'));
    await tester.pumpAndSettle();

    final swipeTarget = find.byKey(const ValueKey('card-detail-swipe-target'));
    expect(swipeTarget, findsOneWidget);

    await tester.drag(swipeTarget, const Offset(0, 140));
    await tester.pumpAndSettle();

    expect(find.text('Open card'), findsOneWidget);
    expect(find.byType(CardDetailScreen), findsNothing);
  });

  testWidgets('additional information pencil opens its editor section', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.tap(find.text('Open card'));
    await tester.pumpAndSettle();

    final editAdditional = find.byKey(
      const ValueKey('edit-additional-information'),
    );
    await tester.ensureVisible(editAdditional);
    await tester.tap(editAdditional);
    await tester.pumpAndSettle();

    expect(find.byType(CardEditScreen), findsOneWidget);
    final section = find.text('Additional Information');
    expect(section, findsOneWidget);
    expect(tester.getTopLeft(section).dy, lessThan(220));
  });
}

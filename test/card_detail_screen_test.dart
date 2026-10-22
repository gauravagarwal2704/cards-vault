import 'package:cards_wallet/models/card_data.dart';
import 'package:cards_wallet/providers/theme_provider.dart';
import 'package:cards_wallet/screens/card_detail_screen.dart';
import 'package:cards_wallet/screens/card_edit_screen.dart';
import 'package:cards_wallet/services/auth_service.dart';
import 'package:cards_wallet/widgets/wallet_card_face.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DetailTestCard extends CardData {
  final bool hasAdditionalInfo;

  _DetailTestCard({this.hasAdditionalInfo = false})
    : super(
        encryptedCardNumber: 'unused',
        encryptedExpiryDate: 'unused',
        lastFourDigits: '1111',
        cardType: 'Visa',
        cardNickname: 'Everyday',
        notes: hasAdditionalInfo ? 'First line\nSecond line' : null,
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
  Future<String?> getDecryptedAccountNumber() async =>
      hasAdditionalInfo ? '001234567890' : null;

  @override
  Future<String?> getDecryptedIfscCode() async =>
      hasAdditionalInfo ? 'HDFC0001234' : null;

  @override
  Future<String?> getDecryptedUpiId() async =>
      hasAdditionalInfo ? 'test@bank' : null;
}

Widget _testApp({bool hasAdditionalInfo = false}) {
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
                    builder: (_) => CardDetailScreen(
                      card: _DetailTestCard(
                        hasAdditionalInfo: hasAdditionalInfo,
                      ),
                      cardIndex: 0,
                    ),
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

  testWidgets('additional information copies each complete saved value', (
    tester,
  ) async {
    final copied = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(_testApp(hasAdditionalInfo: true));
    await tester.tap(find.text('Open card'));
    await tester.pumpAndSettle();
    for (final entry in {
      'Account Number': '001234567890',
      'IFSC Code': 'HDFC0001234',
      'UPI ID': 'test@bank',
      'Notes': 'First line\nSecond line',
    }.entries) {
      final copy = find.byTooltip('Copy ${entry.key}');
      await tester.ensureVisible(copy);
      await tester.pumpAndSettle();
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(copied.last, entry.value);
      expect(find.text('${entry.key} copied'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    }
    expect(copied, hasLength(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty additional fields keep visible disabled copy buttons', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.tap(find.text('Open card'));
    await tester.pumpAndSettle();
    for (final label in ['Account Number', 'IFSC Code', 'UPI ID', 'Notes']) {
      final copy = find.byTooltip('Copy $label');
      expect(copy, findsOneWidget);
      final button = find.ancestor(of: copy, matching: find.byType(IconButton));
      expect(tester.widget<IconButton>(button).onPressed, isNull);
    }
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
    final preview = find.descendant(
      of: find.byType(CardEditScreen),
      matching: find.byType(WalletCardFace),
    );
    final previewBottom = tester.getBottomLeft(preview).dy;
    expect(section.hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(section).dy, greaterThan(previewBottom));
    expect(tester.getTopLeft(section).dy, lessThan(previewBottom + 100));
  });
}

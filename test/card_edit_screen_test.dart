import 'package:cards_wallet/providers/theme_provider.dart';
import 'package:cards_wallet/screens/card_edit_screen.dart';
import 'package:cards_wallet/services/ocr_service.dart';
import 'package:cards_wallet/widgets/card_network_logo.dart';
import 'package:cards_wallet/widgets/wallet_card.dart';
import 'package:cards_wallet/widgets/wallet_card_face.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'card editor uses a compact header save action and previews logo',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final themeProvider = ThemeProvider();
      addTearDown(themeProvider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: themeProvider,
          child: MaterialApp(
            theme: themeProvider.lightTheme,
            home: const CardEditScreen(
              ocrResult: OCRResult(
                cardNumber: '4160210817418901',
                expiryDate: '07/26',
                cardholderName: 'Gaurav Agarwal',
                cardType: 'Visa',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final save = find.byKey(const ValueKey('card-editor-save'));
      expect(save, findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: save),
        findsOneWidget,
      );
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar,
        isNull,
      );

      final logos = tester
          .widgetList<CardNetworkLogo>(find.byType(CardNetworkLogo))
          .toList();
      expect(find.byType(WalletCardFace), findsOneWidget);
      expect(
        tester.widget<WalletCardFace>(find.byType(WalletCardFace)).cardNumber,
        '4160 2108 1741 8901',
      );
      expect(
        logos.any(
          (logo) =>
              logo.forceNetwork == CardNetwork.visa && logo.maxWidth == 100,
        ),
        isTrue,
      );

      await tester.enterText(find.byType(TextField).first, '4160210817411111');
      await tester.pump();
      expect(
        tester.widget<WalletCardFace>(find.byType(WalletCardFace)).cardNumber,
        '4160 2108 1741 1111',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('scan review does not expose OCR diagnostic controls', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final themeProvider = ThemeProvider();
    addTearDown(themeProvider.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeProvider,
        child: MaterialApp(
          theme: themeProvider.lightTheme,
          home: const CardEditScreen(
            ocrResult: OCRResult(
              cardNumber: '4111111111111111',
              expiryDate: '07/30',
              cardholderName: 'Test User',
              cardType: 'Visa',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('View image sent to OCR'), findsNothing);
    expect(find.textContaining('Brightness'), findsNothing);
    expect(find.textContaining('Sharpness'), findsNothing);
  });
}

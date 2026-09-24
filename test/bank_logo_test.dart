import 'package:cards_wallet/data/banks.dart';
import 'package:cards_wallet/widgets/bank_logo.dart';
import 'package:cards_wallet/widgets/wallet_card.dart';
import 'package:cards_wallet/widgets/wallet_card_face.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<SvgPicture> pumpIciciLogo(
    WidgetTester tester,
    Color backgroundColor,
    Color foregroundColor,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: BankLogo(
              bank: Banks.getById('icici'),
              size: 22,
              useSmall: false,
              backgroundColor: backgroundColor,
              foregroundColor: foregroundColor,
              maxWidth: 96,
            ),
          ),
        ),
      ),
    );

    return tester.widget<SvgPicture>(find.byType(SvgPicture));
  }

  Color mappedColor(SvgPicture logo, Color source) {
    final loader = logo.bytesLoader as SvgAssetLoader;
    return loader.colorMapper!.substitute(null, 'path', 'fill', source);
  }

  testWidgets(
    'ICICI card wordmark is transparent with white text on dark cards',
    (tester) async {
      final logo = await pumpIciciLogo(
        tester,
        const Color(0xFFF5F5F5),
        Colors.white,
      );

      expect(logo.colorFilter, isNull);
      expect(mappedColor(logo, const Color(0xFF004A7F)), Colors.white);
      expect(
        mappedColor(logo, const Color(0xFFAE282E)),
        const Color(0xFFAE282E),
      );
      expect(
        find.descendant(
          of: find.byType(BankLogo),
          matching: find.byType(Container),
        ),
        findsNothing,
      );
      expect(tester.getSize(find.byType(BankLogo)).aspectRatio, greaterThan(4));
    },
  );

  testWidgets('ICICI card wordmark uses black text on light cards', (
    tester,
  ) async {
    final logo = await pumpIciciLogo(
      tester,
      const Color(0xFF8B1E23),
      Colors.black,
    );

    expect(mappedColor(logo, const Color(0xFF004A7F)), Colors.black);
  });

  testWidgets('American Express issuer uses the full wordmark on dark cards', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BankLogo(
            bank: Banks.getById('amex'),
            size: 30,
            useSmall: false,
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );

    final logo = tester.widget<SvgPicture>(find.byType(SvgPicture));
    final loader = logo.bytesLoader as SvgAssetLoader;
    expect(loader.assetName, 'assets/networks/amex.svg');
    expect(logo.colorFilter, isNotNull);
  });

  testWidgets('AMEX preview puts full issuer and compact network logos', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 227,
            child: WalletCardFace(
              bank: null,
              network: CardNetwork.amex,
              categoryName: 'Credit',
              nickname: 'Travel',
              cardNumber: '•••• •••••• •1007',
              cardholderName: 'Test User',
              expiryDate: '12/30',
              backgroundColor: Color(0xFF1144CC),
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BankLogo), findsOneWidget);
    final logos = tester
        .widgetList<SvgPicture>(find.byType(SvgPicture))
        .toList();
    final assetNames = logos
        .map((logo) => (logo.bytesLoader as SvgAssetLoader).assetName)
        .toList();

    expect(assetNames, [
      'assets/networks/amex.svg',
      'assets/networks/amex-small.svg',
    ]);
    expect(logos.first.colorFilter, isNotNull);
    expect(logos.last.colorFilter, isNull);
  });
}

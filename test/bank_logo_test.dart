import 'package:cards_wallet/data/banks.dart';
import 'package:cards_wallet/widgets/bank_logo.dart';
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
}

import 'package:cards_wallet/widgets/wallet_card_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('card text keeps a non-decorated style during Hero flight', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                const WalletCardHero(
                  tag: 'card',
                  child: SizedBox(
                    width: 220,
                    height: 140,
                    child: Text(
                      'CARD FACE',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        body: Align(
                          alignment: Alignment.topCenter,
                          child: WalletCardHero(
                            tag: 'card',
                            child: SizedBox(
                              width: 320,
                              height: 200,
                              child: Text(
                                'CARD FACE',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    void expectUndecoratedFlightText() {
      final flightText = tester
          .widgetList<RichText>(find.byType(RichText))
          .where((widget) => widget.text.toPlainText() == 'CARD FACE')
          .single;
      final style = (flightText.text as TextSpan).style;

      expect(style?.decoration, TextDecoration.none);
      expect(style?.decorationColor, isNot(const Color(0xFFFFFF00)));
    }

    expectUndecoratedFlightText();

    await tester.pumpAndSettle();
    navigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expectUndecoratedFlightText();
  });
}

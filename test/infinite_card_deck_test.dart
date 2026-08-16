import 'package:cards_wallet/models/card_data.dart';
import 'package:cards_wallet/widgets/infinite_card_deck.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CardData _card(int index) => CardData(
  encryptedCardNumber: 'encrypted-$index',
  encryptedExpiryDate: 'encrypted-expiry-$index',
  lastFourDigits: index.toString().padLeft(4, '0'),
  cardType: 'visa',
  id: 'card-$index',
);

Widget _deck({ValueChanged<int>? onCardChanged}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          height: 520,
          child: InfiniteCardDeck(
            cards: List.generate(8, _card),
            onCardChanged: onCardChanged,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('large decks render a bounded seven-card depth window', (
    tester,
  ) async {
    await tester.pumpWidget(_deck());
    await tester.pump();

    final renderedCards = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('deck-card-');
    });

    expect(renderedCards, findsNWidgets(7));
    expect(find.text('1 / 8'), findsOneWidget);

    final lowestCardBottom = renderedCards
        .evaluate()
        .map(
          (element) => tester
              .getBottomRight(find.byElementPredicate((e) => e == element))
              .dy,
        )
        .reduce((a, b) => a > b ? a : b);
    final indicatorTop = tester.getTopLeft(find.text('1 / 8')).dy;

    expect(indicatorTop, greaterThan(lowestCardBottom));
    expect(indicatorTop - lowestCardBottom, lessThan(64));
  });

  testWidgets('vertical movement settles on a card with spring physics', (
    tester,
  ) async {
    int? selectedIndex;
    await tester.pumpWidget(
      _deck(onCardChanged: (index) => selectedIndex = index),
    );
    await tester.pump();

    await tester.timedDrag(
      find.byType(InfiniteCardDeck),
      const Offset(0, -150),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();

    expect(selectedIndex, isNotNull);
    expect(selectedIndex, isNot(0));
    expect(find.text('1 / 8'), findsNothing);
  });

  testWidgets('horizontal card actions do not move the vertical carousel', (
    tester,
  ) async {
    int? selectedIndex;
    await tester.pumpWidget(
      _deck(onCardChanged: (index) => selectedIndex = index),
    );
    await tester.pump();

    await tester.drag(
      find.byKey(const ValueKey('deck-swipe-card-0')),
      const Offset(-180, 0),
    );
    await tester.pumpAndSettle();

    expect(selectedIndex, isNull);
    expect(find.text('1 / 8'), findsOneWidget);
  });
}

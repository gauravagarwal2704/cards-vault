import 'package:cards_wallet/models/card_data.dart';
import 'package:cards_wallet/widgets/card_tiles_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CardData _card(String id, String lastFour) => CardData(
  encryptedCardNumber: 'enc',
  encryptedExpiryDate: 'enc',
  lastFourDigits: lastFour,
  cardType: 'visa',
  id: id,
);

Widget _host({
  required List<CardData> cards,
  Set<String> selectedCardIds = const {},
  bool selectionMode = false,
  ValueChanged<CardData>? onLongPress,
}) {
  return MaterialApp(
    home: Scaffold(
      body: CardTilesGrid(
        cards: cards,
        selectedCardIds: selectedCardIds,
        selectionMode: selectionMode,
        onCardLongPress: onLongPress,
      ),
    ),
  );
}

void main() {
  testWidgets('long press exposes a card to bulk selection', (tester) async {
    final cards = [_card('first', '1111'), _card('second', '2222')];
    CardData? longPressed;

    await tester.pumpWidget(
      _host(cards: cards, onLongPress: (card) => longPressed = card),
    );
    await tester.longPress(find.text('•••• 1111'));

    expect(longPressed?.id, 'first');
  });

  testWidgets('selection mode marks only selected cards', (tester) async {
    final cards = [_card('first', '1111'), _card('second', '2222')];

    await tester.pumpWidget(
      _host(
        cards: cards,
        selectedCardIds: const {'first'},
        selectionMode: true,
      ),
    );

    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}

import 'package:cards_wallet/models/card_data.dart';
import 'package:cards_wallet/providers/theme_provider.dart';
import 'package:cards_wallet/widgets/stacked_card_grid.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Built through the raw constructor so the test never touches secure storage;
/// the grid only reads plaintext fields.
CardData _card(String lastFour) => CardData(
      encryptedCardNumber: 'enc',
      encryptedExpiryDate: 'enc',
      lastFourDigits: lastFour,
      cardType: 'visa',
      id: 'id-$lastFour',
    );

CardStack _stack(String key, int count) => CardStack(
      key: key,
      title: key,
      cards: List.generate(count, (i) => _card('$key$i')),
    );

/// An ungrouped card, which is what a drag can pick up.
CardStack _looseStack(String key) => CardStack(
      key: key,
      title: key,
      cards: [_card(key)],
    );

/// A custom group, which can only receive drops.
CardStack _groupStack(String key, int count) => CardStack(
      key: key,
      title: key,
      groupId: key,
      cards: List.generate(count, (i) => _card('$key$i')),
    );

Widget _host({
  required List<CardStack> stacks,
  required String axisKey,
  bool canGroupByDrag = false,
  void Function(CardData card, CardStack target)? onDropOnStack,
}) {
  return ChangeNotifierProvider<ThemeProvider>(
    create: (_) => ThemeProvider(),
    child: MaterialApp(
      home: Scaffold(
        body: StackedCardGrid(
          stacks: stacks,
          axisKey: axisKey,
          canGroupByDrag: canGroupByDrag,
          onDropOnStack: onDropOnStack,
        ),
      ),
    ),
  );
}

/// Long-press drags the tile for [fromKey] onto the tile for [toKey].
Future<void> _dragTile(
  WidgetTester tester,
  String fromKey,
  String toKey,
) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(ValueKey(fromKey))),
  );
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
  await gesture.moveTo(tester.getCenter(find.byKey(ValueKey(toKey))));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Opacity the regroup animation is currently applying to the tile for [key].
/// The grid keys each tile's entry animation by its stack key, and that wrapper's
/// own [Opacity] is the outermost one inside it.
double _tileOpacity(WidgetTester tester, String key) {
  final finder = find
      .descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Opacity),
      )
      .first;
  return tester.widget<Opacity>(finder).opacity;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tiles animate in rather than appearing fully formed',
      (tester) async {
    await tester.pumpWidget(_host(
      stacks: [_stack('Axis', 3), _stack('HDFC', 2)],
      axisKey: 'bank',
    ));

    expect(_tileOpacity(tester, 'Axis'), 0.0);

    await tester.pumpAndSettle();
    expect(_tileOpacity(tester, 'Axis'), 1.0);
  });

  testWidgets('changing the grouping axis replays the animation',
      (tester) async {
    await tester.pumpWidget(_host(
      stacks: [_stack('Axis', 3), _stack('HDFC', 2)],
      axisKey: 'bank',
    ));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_host(
      stacks: [_stack('Credit', 4), _stack('Debit', 1)],
      axisKey: 'type',
    ));
    await tester.pump();

    // The new arrangement starts transparent and settles into place.
    expect(_tileOpacity(tester, 'Credit'), 0.0);
    await tester.pumpAndSettle();
    expect(_tileOpacity(tester, 'Credit'), 1.0);
    expect(find.text('Axis'), findsNothing);
  });

  testWidgets('tiles settle in reading order', (tester) async {
    await tester.pumpWidget(_host(
      stacks: [_stack('First', 2), _stack('Second', 2), _stack('Third', 2)],
      axisKey: 'bank',
    ));

    // The leading tile needs a tick to start before time can be advanced on it;
    // tiles later in reading order are still waiting out their stagger delay.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 130));
    final first = _tileOpacity(tester, 'First');
    final third = _tileOpacity(tester, 'Third');

    expect(first, greaterThan(third));
    await tester.pumpAndSettle();
  });

  testWidgets('a multi-card stack expands to show every member',
      (tester) async {
    await tester.pumpWidget(_host(
      stacks: [_stack('Axis', 3)],
      axisKey: 'bank',
    ));
    await tester.pumpAndSettle();

    // Only the front card is rendered; the ones behind it are bare silhouettes.
    expect(find.text('•••• Axis2'), findsNothing);

    await tester.tap(find.text('•••• Axis0').first);
    await tester.pumpAndSettle();

    expect(find.text('3 cards'), findsOneWidget);
    expect(find.text('•••• Axis2'), findsOneWidget);
  });

  group('drag to group', () {
    testWidgets('tiles are not draggable unless grouping by drag is on',
        (tester) async {
      await tester.pumpWidget(_host(
        stacks: [_looseStack('loose'), _groupStack('Axis', 2)],
        axisKey: 'custom',
      ));
      await tester.pumpAndSettle();

      expect(find.byType(LongPressDraggable<CardData>), findsNothing);
    });

    testWidgets('only loose cards are draggable, groups are drop targets only',
        (tester) async {
      await tester.pumpWidget(_host(
        stacks: [_looseStack('loose'), _groupStack('Axis', 2)],
        axisKey: 'custom',
        canGroupByDrag: true,
      ));
      await tester.pumpAndSettle();

      // Both tiles accept a drop, but only the ungrouped one can be picked up.
      expect(find.byType(LongPressDraggable<CardData>), findsOneWidget);
      expect(find.byType(DragTarget<CardData>), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('Axis')),
          matching: find.byType(LongPressDraggable<CardData>),
        ),
        findsNothing,
      );
    });

    testWidgets('dropping a loose card on a group reports that group',
        (tester) async {
      CardData? dropped;
      CardStack? target;

      await tester.pumpWidget(_host(
        stacks: [_looseStack('loose'), _groupStack('Axis', 2)],
        axisKey: 'custom',
        canGroupByDrag: true,
        onDropOnStack: (card, stack) {
          dropped = card;
          target = stack;
        },
      ));
      await tester.pumpAndSettle();

      await _dragTile(tester, 'loose', 'Axis');

      expect(dropped?.id, 'id-loose');
      expect(target?.groupId, 'Axis');
    });

    testWidgets('dropping a loose card on another loose card reports the pair',
        (tester) async {
      CardStack? target;

      await tester.pumpWidget(_host(
        stacks: [_looseStack('first'), _looseStack('second')],
        axisKey: 'custom',
        canGroupByDrag: true,
        onDropOnStack: (card, stack) => target = stack,
      ));
      await tester.pumpAndSettle();

      await _dragTile(tester, 'first', 'second');

      expect(target?.isLooseCard, isTrue);
      expect(target?.cards.single.id, 'id-second');
    });

    testWidgets('dropping a card back on itself changes nothing',
        (tester) async {
      var drops = 0;

      await tester.pumpWidget(_host(
        stacks: [_looseStack('loose'), _groupStack('Axis', 2)],
        axisKey: 'custom',
        canGroupByDrag: true,
        onDropOnStack: (card, stack) => drops++,
      ));
      await tester.pumpAndSettle();

      await _dragTile(tester, 'loose', 'loose');

      expect(drops, 0);
    });
  });
}

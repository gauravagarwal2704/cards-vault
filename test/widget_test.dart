import 'package:cards_wallet/main.dart';
import 'package:cards_wallet/models/card_data.dart';
import 'package:cards_wallet/models/card_group.dart';
import 'package:cards_wallet/providers/card_view_provider.dart';
import 'package:cards_wallet/providers/app_lock_provider.dart';
import 'package:cards_wallet/providers/nfc_provider.dart';
import 'package:cards_wallet/providers/profile_provider.dart';
import 'package:cards_wallet/providers/theme_provider.dart';
import 'package:cards_wallet/providers/app_icon_provider.dart';
import 'package:cards_wallet/screens/saved_cards_screen.dart';
import 'package:cards_wallet/screens/developer_options_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<List<CardData>> _loadNoCards() async => [];

Future<List<CardGroup>> _loadNoGroups() async => [];

CardData _testCard(String id, String lastFour) => CardData(
  encryptedCardNumber: 'encrypted',
  encryptedExpiryDate: 'encrypted',
  lastFourDigits: lastFour,
  cardType: 'visa',
  id: id,
);

Future<List<CardData>> _loadTestCards() async => [
  _testCard('first', '1111'),
  _testCard('second', '2222'),
];

Future<List<CardData>> _loadCardWithUnreadableName() async => [
  _UnreadableNameCard(),
];

class _UnreadableNameCard extends CardData {
  _UnreadableNameCard()
    : super(
        encryptedCardNumber: 'encrypted',
        encryptedExpiryDate: 'encrypted',
        lastFourDigits: '4242',
        cardType: 'visa',
        id: 'unreadable-name',
      );

  @override
  Future<String?> getDecryptedCardholderName() async {
    throw Exception('Decryption failed');
  }
}

Widget _home({required Future<List<CardData>> Function() cardLoader}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => NfcProvider()),
      ChangeNotifierProvider(create: (_) => CardViewProvider()),
      ChangeNotifierProvider(create: (_) => AppLockProvider()),
      ChangeNotifierProvider(create: (_) => ProfileProvider()),
      ChangeNotifierProvider(create: (_) => AppIconProvider()),
    ],
    child: MaterialApp(
      home: SavedCardsScreen(
        cardLoader: cardLoader,
        groupLoader: _loadNoGroups,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('new users see onboarding and their saved greeting', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MyApp());
    expect(find.byKey(const ValueKey('splash')), findsNothing);

    await tester.pumpAndSettle();

    expect(find.text('Welcome to\nCardVault'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-name-field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('onboarding-name-field')),
      'Gaurav',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('onboarding-continue')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('onboarding-continue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('profile_display_name'), 'Gaurav');
    expect(find.text('Welcome back, Gaurav'), findsOneWidget);
  });

  testWidgets('returning users skip onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({'profile_display_name': 'Avery'});

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Welcome back, Avery'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('locked startup exposes a valid semantic route', (tester) async {
    SharedPreferences.setMockInitialValues({
      'profile_display_name': 'Avery',
      'app_lock_enabled': true,
    });
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('CardVault is locked'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'CardVault locked')), findsOneWidget);
    expect(tester.takeException(), isNull);

    semantics.dispose();
  });

  testWidgets('display name dialog can be cancelled and saved safely', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'profile_display_name': 'Avery'});

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Avery'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('display-name-cancel')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Avery'), findsOneWidget);

    await tester.tap(find.text('Avery'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('display-name-field')),
      '  Gaurav  ',
    );
    await tester.tap(find.byKey(const ValueKey('display-name-save')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Gaurav'), findsOneWidget);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('profile_display_name'), 'Gaurav');
  });

  testWidgets('empty state stays centered in every card view', (tester) async {
    SharedPreferences.setMockInitialValues({'profile_display_name': 'Avery'});

    await tester.pumpWidget(_home(cardLoader: _loadNoCards));
    await tester.pump(const Duration(milliseconds: 500));

    final homeContext = tester.element(find.byType(SavedCardsScreen));
    final viewProvider = Provider.of<CardViewProvider>(
      homeContext,
      listen: false,
    );
    final carouselY = tester.getCenter(find.text('No saved cards')).dy;

    await viewProvider.setViewMode(CardViewMode.grid);
    await tester.pump(const Duration(milliseconds: 300));
    final gridY = tester.getCenter(find.text('No saved cards')).dy;

    await viewProvider.setViewMode(CardViewMode.stackedGrid);
    await tester.pump(const Duration(milliseconds: 300));
    final stackedGridY = tester.getCenter(find.text('No saved cards')).dy;

    expect(gridY, closeTo(carouselY, 0.01));
    expect(stackedGridY, closeTo(carouselY, 0.01));
  });

  testWidgets('filter sheet header and content share a left edge', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'profile_display_name': 'Avery'});

    await tester.pumpWidget(_home(cardLoader: _loadNoCards));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();

    final titleLeft = tester
        .getTopLeft(find.byKey(const ValueKey('filter-sheet-title')))
        .dx;
    final contentLeft = tester
        .getTopLeft(find.byKey(const ValueKey('filter-sheet-content')))
        .dx;

    expect(contentLeft, closeTo(titleLeft, 0.01));
  });

  testWidgets('long press enters bulk selection outside custom stacks', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile_display_name': 'Avery',
      'card_view_mode': 'grid',
    });

    await tester.pumpWidget(_home(cardLoader: _loadTestCards));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.longPress(find.text('•••• 1111'));
    await tester.pump();
    expect(find.byKey(const ValueKey('bulk-selection-count')), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byKey(const ValueKey('bulk-share')), findsOneWidget);
    expect(find.byKey(const ValueKey('bulk-delete')), findsOneWidget);

    await tester.tap(find.text('•••• 2222'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
  });

  testWidgets('an unreadable cardholder name does not block saved cards', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile_display_name': 'Avery',
      'card_view_mode': 'grid',
    });

    await tester.pumpWidget(_home(cardLoader: _loadCardWithUnreadableName));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('•••• 4242'), findsOneWidget);
    expect(
      find.textContaining('encrypted details that could not be read'),
      findsOneWidget,
    );
    expect(find.textContaining('Failed to load cards'), findsNothing);
  });

  testWidgets('custom stacked grid keeps long press for grouping', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile_display_name': 'Avery',
      'card_view_mode': 'stackedGrid',
      'card_stack_by': 'custom',
    });

    await tester.pumpWidget(_home(cardLoader: _loadTestCards));
    await tester.pump(const Duration(milliseconds: 700));

    await tester.longPress(find.text('•••• 1111'));
    await tester.pump();

    expect(find.byKey(const ValueKey('bulk-selection-count')), findsNothing);
  });

  testWidgets('settings shows a disabled delete-all action when empty', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'profile_display_name': 'Avery'});

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    final deleteAll = find.byKey(const ValueKey('delete-all-cards'));
    expect(deleteAll, findsOneWidget);
    expect(tester.widget<InkWell>(deleteAll).onTap, isNull);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/branding/app_icon_3d.png',
      ),
      findsOneWidget,
    );
  });

  testWidgets('returning from unchanged settings keeps the loaded wallet', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile_display_name': 'Avery',
      'card_view_mode': 'grid',
    });
    var loadCount = 0;

    await tester.pumpWidget(
      _home(
        cardLoader: () async {
          loadCount++;
          return _loadTestCards();
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(loadCount, 1);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(loadCount, 1);
    expect(find.text('•••• 1111'), findsOneWidget);
    expect(find.text('•••• 2222'), findsOneWidget);
  });

  testWidgets('five app version taps reveal the developer options page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'profile_display_name': 'Avery'});

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    final version = find.byKey(const ValueKey('app-version-developer-unlock'));
    expect(find.text('CardVault'), findsOneWidget);
    expect(version, findsOneWidget);
    expect(find.byKey(const ValueKey('developer-options-entry')), findsNothing);

    await tester.tap(version);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(version);
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text('3 more taps to unlock developer options'),
      findsOneWidget,
    );

    for (var tap = 2; tap < 5; tap++) {
      await tester.tap(version);
      await tester.pump();
    }

    final developerOptions = find.byKey(
      const ValueKey('developer-options-entry'),
    );
    await tester.ensureVisible(developerOptions);
    await tester.pumpAndSettle();
    expect(developerOptions, findsOneWidget);

    await tester.tap(developerOptions);
    await tester.pumpAndSettle();
    expect(find.byType(DeveloperOptionsScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('test-authentication-developer-option')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('developer-options-enabled-toggle')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DeveloperOptionsScreen), findsNothing);
    expect(developerOptions, findsNothing);
  });
}

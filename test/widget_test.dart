import 'dart:async';

import 'package:cards_wallet/main.dart';
import 'package:cards_wallet/models/card_data.dart';
import 'package:cards_wallet/models/app_release.dart';
import 'package:cards_wallet/models/card_group.dart';
import 'package:cards_wallet/providers/card_view_provider.dart';
import 'package:cards_wallet/providers/app_lock_provider.dart';
import 'package:cards_wallet/providers/nfc_provider.dart';
import 'package:cards_wallet/providers/profile_provider.dart';
import 'package:cards_wallet/providers/theme_provider.dart';
import 'package:cards_wallet/providers/app_icon_provider.dart';
import 'package:cards_wallet/screens/saved_cards_screen.dart';
import 'package:cards_wallet/screens/developer_options_screen.dart';
import 'package:cards_wallet/screens/feedback_support_screen.dart';
import 'package:cards_wallet/widgets/card_tiles_grid.dart';
import 'package:cards_wallet/widgets/stacked_card_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

Future<List<CardData>> _loadCardsWithCaseVariantNames() async => [
  _NamedCard(id: 'first', lastFour: '1111', name: 'jOhN doE'),
  _NamedCard(id: 'second', lastFour: '2222', name: 'JOHN DOE'),
];

class _NamedCard extends CardData {
  final String name;

  _NamedCard({required String id, required String lastFour, required this.name})
    : super(
        encryptedCardNumber: 'encrypted',
        encryptedExpiryDate: 'encrypted',
        lastFourDigits: lastFour,
        cardType: 'visa',
        id: id,
      );

  @override
  Future<String?> getDecryptedCardholderName() async => name;
}

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

class _PendingNameCard extends CardData {
  _PendingNameCard(this.name)
    : super(
        encryptedCardNumber: 'encrypted',
        encryptedExpiryDate: 'encrypted',
        lastFourDigits: '4242',
        cardType: 'visa',
        id: 'pending-name',
      );

  final Future<String?> name;

  @override
  Future<String?> getDecryptedCardholderName() => name;
}

Widget _home({
  required Future<List<CardData>> Function() cardLoader,
  Future<List<CardGroup>> Function()? groupLoader,
}) {
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
        groupLoader: groupLoader ?? _loadNoGroups,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Appearance indicator follows device colors after a custom color',
    (tester) async {
      SharedPreferences.setMockInitialValues({'profile_display_name': 'Avery'});
      const channel = MethodChannel('cards_wallet/appearance');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          for (final family in [
            'accent1',
            'accent2',
            'accent3',
            'neutral1',
            'neutral2',
          ])
            family: {
              for (final tone in [
                0,
                10,
                20,
                30,
                40,
                50,
                60,
                70,
                80,
                90,
                95,
                99,
                100,
              ])
                '$tone': Color.lerp(
                  Colors.black,
                  Colors.white,
                  tone / 100,
                )!.toARGB32(),
            },
          'light': {'primary': 0xFF226644},
          'dark': {'primary': 0xFF99CCAA},
        },
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(_home(cardLoader: _loadNoCards));
      await tester.pumpAndSettle();
      final provider = tester
          .element(find.byType(SavedCardsScreen))
          .read<ThemeProvider>();
      await provider.setCustomSeedColor(const Color(0xFFAA33CC));
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      final indicator = find.byKey(const ValueKey('appearance-active-color'));
      expect(
        (tester.widget<Container>(indicator).decoration as BoxDecoration).color,
        provider.getPrimaryColor(),
      );
      await provider.useSystemColorSource();
      await tester.pumpAndSettle();
      expect(provider.getPrimaryColor().toARGB32(), 0xFF226644);
      expect(
        (tester.widget<Container>(indicator).decoration as BoxDecoration).color,
        provider.getPrimaryColor(),
      );
      expect(provider.seedColor, const Color(0xFFAA33CC));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('new users see onboarding and app lock defaults to enabled', (
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
    expect(find.text('CardVault is locked'), findsOneWidget);
  });

  testWidgets('returning users skip onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({
      'profile_display_name': 'Avery',
      'app_lock_enabled': false,
    });

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
    SharedPreferences.setMockInitialValues({
      'profile_display_name': 'Avery',
      'app_lock_enabled': false,
    });

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

    await viewProvider.setViewMode(CardViewMode.stackedGrid);
    await tester.pump(const Duration(milliseconds: 300));
    final stackedGridY = tester.getCenter(find.text('No saved cards')).dy;

    expect(stackedGridY, closeTo(carouselY, 0.01));
  });

  testWidgets('grid lives inside Stacks as the no-grouping option', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'profile_display_name': 'Avery'});

    await tester.pumpWidget(_home(cardLoader: _loadTestCards));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Grid'), findsNothing);
    expect(find.text('Carousel'), findsOneWidget);
    expect(find.text('Stacks'), findsOneWidget);

    await tester.tap(find.text('Stacks'));
    await tester.pumpAndSettle();

    expect(find.text('No grouping'), findsOneWidget);
    expect(find.byType(CardTilesGrid), findsOneWidget);
  });

  testWidgets('legacy grid preference migrates to ungrouped stacks', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile_display_name': 'Avery',
      'card_view_mode': 'grid',
      'card_stack_by': 'bank',
    });

    await tester.pumpWidget(_home(cardLoader: _loadTestCards));
    await tester.pump(const Duration(milliseconds: 700));

    final provider = Provider.of<CardViewProvider>(
      tester.element(find.byType(SavedCardsScreen)),
      listen: false,
    );
    expect(provider.viewMode, CardViewMode.stackedGrid);
    expect(provider.stackBy, CardStackBy.none);
    expect(find.byType(CardTilesGrid), findsOneWidget);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('card_view_mode'), 'stackedGrid');
    expect(preferences.getString('card_stack_by'), 'none');
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

  testWidgets('cardholder filters ignore case and keep the avatar centered', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile_display_name': 'Avery',
      'card_view_mode': 'grid',
    });

    await tester.pumpWidget(_home(cardLoader: _loadCardsWithCaseVariantNames));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pumpAndSettle();

    expect(find.text('John Doe'), findsOneWidget);
    expect(find.text('john doe'), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('cardholder-avatar-john doe'))),
      const Size.square(20),
    );
    expect(
      tester
          .widget<Padding>(
            find.byKey(const ValueKey('cardholder-avatar-padding-john doe')),
          )
          .padding,
      const EdgeInsets.all(3),
    );

    await tester.tap(find.text('John Doe'));
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();

    expect(find.text('•••• 1111'), findsOneWidget);
    expect(find.text('•••• 2222'), findsOneWidget);
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

  testWidgets(
    'cards render before groups and cardholder search details finish',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'profile_display_name': 'Avery',
        'card_view_mode': 'grid',
      });
      final groups = Completer<List<CardGroup>>();
      final name = Completer<String?>();
      final card = _PendingNameCard(name.future);
      await tester.pumpWidget(
        _home(cardLoader: () async => [card], groupLoader: () => groups.future),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('•••• 4242'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      groups.complete([]);
      await tester.pump();
      expect(find.text('•••• 4242'), findsOneWidget);
      name.complete('Avery');
      await tester.pumpAndSettle();
      expect(find.text('•••• 4242'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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

    expect(find.byKey(const ValueKey('custom-stack-guidance')), findsOneWidget);
    expect(
      find.text('Drag a card onto another to create a stack.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('custom-stack-drag-demo')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('custom-stack-demo-hand')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('custom-stack-demo-top-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('custom-stack-demo-bottom-card')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('custom-stack-demo-bottom-card')),
          )
          .opacity,
      0,
    );
    await tester.pump(const Duration(milliseconds: 3400));
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('custom-stack-demo-bottom-card')),
          )
          .opacity,
      1,
    );
    await tester.pump(const Duration(milliseconds: 2400));
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('custom-stack-demo-cycle')),
          )
          .opacity,
      0,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const ValueKey('custom-stack-demo-cycle')),
          )
          .opacity,
      0,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('custom-stack-guidance-text')),
          )
          .maxLines,
      1,
    );

    await tester.ensureVisible(find.text('•••• 1111'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.longPress(find.text('•••• 1111'));
    await tester.pump();

    expect(find.byKey(const ValueKey('bulk-selection-count')), findsNothing);
  });

  testWidgets('custom axis keeps the existing grid while guidance appears', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile_display_name': 'Avery',
      'card_view_mode': 'stackedGrid',
      'card_stack_by': 'type',
    });

    await tester.pumpWidget(_home(cardLoader: _loadTestCards));
    await tester.pumpAndSettle();

    final initialGridState = tester.state(find.byType(StackedCardGrid));

    await tester.tap(find.text('Custom'));
    await tester.pump();

    expect(find.byKey(const ValueKey('custom-stack-guidance')), findsOneWidget);
    expect(tester.state(find.byType(StackedCardGrid)), same(initialGridState));

    await tester.tap(find.text('Type'));
    await tester.pump();

    expect(find.byKey(const ValueKey('custom-stack-guidance')), findsNothing);
    expect(tester.state(find.byType(StackedCardGrid)), same(initialGridState));
  });

  testWidgets('settings shows a disabled delete-all action when empty', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile_display_name': 'Avery',
      'app_lock_enabled': false,
    });

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    final deleteAll = find.byKey(const ValueKey('delete-all-cards'));
    expect(deleteAll, findsOneWidget);
    expect(tester.widget<InkWell>(deleteAll).onTap, isNull);
    expect(find.text('Smart AI scan'), findsNothing);
    expect(find.text('Smart scan'), findsNothing);
    expect(
      find.byKey(const ValueKey('github-repository-link')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('github-logo')), findsOneWidget);
    expect(find.byKey(const ValueKey('about-links-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('telegram-link')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('support-developer-link')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('support-developer-app-icon')),
      findsOneWidget,
    );
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('Telegram'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);

    final linkKeys = [
      'github-repository-link',
      'telegram-link',
      'support-developer-link',
    ];
    final linkCenters = linkKeys
        .map((key) => tester.getCenter(find.byKey(ValueKey(key))))
        .toList();
    for (final center in linkCenters.skip(1)) {
      expect(center.dy, closeTo(linkCenters.first.dy, 0.01));
    }
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('about-links-row'))).dy,
      greaterThan(
        tester
            .getBottomLeft(
              find.byKey(const ValueKey('app-version-developer-unlock')),
            )
            .dy,
      ),
    );
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('about-links-row'))).dy,
      lessThan(tester.getTopLeft(find.text('Profile')).dy),
    );
    expect(find.byKey(const ValueKey('privacy-policy-link')), findsOneWidget);
    expect(
      find.text('gauravagarwal2704.github.io/cards-vault/privacy-policy.html'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('open-source-licenses-link')),
      findsOneWidget,
    );
    expect(
      find.text('Libraries and licenses used by CardVault'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/branding/app_icon_3d.webp',
      ),
      findsOneWidget,
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1600));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('change-history-link')),
    );
    await tester.tap(find.byKey(const ValueKey('change-history-link')));
    await tester.pumpAndSettle();
    expect(find.text('Change history'), findsOneWidget);
    expect(
      find.text('Version ${AppRelease.history.first.version}'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('open-source-licenses-link')),
    );
    await tester.tap(find.byKey(const ValueKey('open-source-licenses-link')));
    await tester.pumpAndSettle();

    expect(find.text('Licenses'), findsOneWidget);
    expect(find.text('Open-source software licenses'), findsOneWidget);
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
    SharedPreferences.setMockInitialValues({
      'profile_display_name': 'Avery',
      'app_lock_enabled': false,
    });

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
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'developer_options_enabled',
      ),
      isTrue,
    );

    await tester.tap(developerOptions);
    await tester.pumpAndSettle();
    expect(find.byType(DeveloperOptionsScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('test-authentication-developer-option')),
      findsOneWidget,
    );
    expect(find.text('Logs capture'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('share-logs-developer-option')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('share-logs-developer-option')));
    await tester.pumpAndSettle();
    expect(find.byType(FeedbackSupportScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('developer-options-enabled-toggle')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DeveloperOptionsScreen), findsNothing);
    expect(developerOptions, findsNothing);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('developer_options_enabled'), isFalse);
  });

  testWidgets('developer options opt-in is restored in a new settings screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'profile_display_name': 'Avery',
      'app_lock_enabled': false,
      'developer_options_enabled': true,
    });

    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    final developerOptions = find.byKey(
      const ValueKey('developer-options-entry'),
    );
    await tester.ensureVisible(developerOptions);
    expect(developerOptions, findsOneWidget);
  });
}

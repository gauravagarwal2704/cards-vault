import 'package:cards_wallet/models/theme_config.dart' as config;
import 'package:cards_wallet/providers/theme_provider.dart';
import 'package:cards_wallet/providers/app_icon_provider.dart';
import 'package:cards_wallet/screens/appearance_screen.dart';
import 'package:cards_wallet/theme/app_colors.dart';
import 'package:cards_wallet/theme/app_motion.dart';
import 'package:cards_wallet/widgets/app_icon_artwork.dart';
import 'package:cards_wallet/widgets/app_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('cards_wallet/appearance'),
          (_) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('cards_wallet/appearance'),
          null,
        );
  });

  testWidgets(
    'device style examples differ and compact color tiles keep all circles visible',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider();
      final icons = AppIconProvider();
      addTearDown(provider.dispose);
      addTearDown(icons.dispose);
      await tester.pump();
      await provider.useSystemColorSource();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider.value(value: icons),
          ],
          child: MaterialApp(
            theme: provider.lightTheme,
            home: const AppearanceScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Color previewPrimary(String style) {
        final buttons = find.descendant(
          of: find.byKey(ValueKey('palette-style-$style')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.decoration is ShapeDecoration &&
                (widget.decoration as ShapeDecoration).shape is StadiumBorder,
          ),
        );
        return (tester.widget<Container>(buttons.first).decoration
                as ShapeDecoration)
            .color!;
      }

      expect(previewPrimary('tonalSpot'), isNot(previewPrimary('expressive')));
      for (final strategy in config.AppPaletteStrategy.values) {
        expect(
          previewPrimary(strategy.name),
          ColorScheme.fromSeed(
            seedColor: provider.colorScheme.primary,
            dynamicSchemeVariant: strategy.schemeVariant,
          ).primary,
        );
      }
      final device = find.byKey(const ValueKey('device-colors-tile'));
      await tester.scrollUntilVisible(
        device,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.getSize(device).height, lessThanOrEqualTo(76));
      final tile = find.byKey(const ValueKey('color-theme-indigo'));
      await tester.scrollUntilVisible(
        tile,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.getSize(tile).height, lessThan(90));
      final ocean = find.byKey(const ValueKey('color-theme-ocean'));
      expect(
        tester.getTopLeft(ocean).dx - tester.getTopRight(tile).dx,
        closeTo(12, 0.01),
      );
      final stack = find.descendant(of: tile, matching: find.byType(Stack));
      final bounds = tester.getRect(stack);
      for (final element
          in find
              .descendant(of: stack, matching: find.byType(Positioned))
              .evaluate()) {
        final circle = tester.getRect(
          find.byElementPredicate((candidate) => candidate == element),
        );
        expect(circle.left, greaterThanOrEqualTo(bounds.left));
        expect(circle.right, lessThanOrEqualTo(bounds.right));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('theme provider exposes every expressive appearance mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final provider = ThemeProvider();
    addTearDown(provider.dispose);
    await tester.pump();

    expect(provider.lightTheme.useMaterial3, isTrue);
    expect(provider.darkTheme.useMaterial3, isTrue);
    expect(provider.lightTheme.extension<AppSemanticColors>(), isNotNull);
    expect(provider.darkTheme.extension<AppSemanticColors>(), isNotNull);
    expect(provider.lightTheme.chipTheme.showCheckmark, isFalse);
    expect(provider.darkTheme.chipTheme.showCheckmark, isFalse);
    expect(provider.paletteStrategy, config.AppPaletteStrategy.tonalSpot);
    expect(provider.materialThemeMode, ThemeMode.system);

    await provider.setBrightnessMode(config.AppBrightnessMode.amoled);
    expect(provider.materialThemeMode, ThemeMode.dark);
    expect(provider.isAmoled, isTrue);
    expect(provider.materialDarkTheme.scaffoldBackgroundColor, Colors.black);
    expect(provider.materialDarkTheme.colorScheme.surface, Colors.black);

    await provider.setBrightnessMode(config.AppBrightnessMode.light);
    expect(provider.materialThemeMode, ThemeMode.light);
    await provider.setBrightnessMode(config.AppBrightnessMode.dark);
    expect(provider.materialThemeMode, ThemeMode.dark);
  });

  testWidgets('device, preset, and custom color sources persist', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final provider = ThemeProvider();
    addTearDown(provider.dispose);
    await tester.pump();

    await provider.useSystemColorSource();
    expect(provider.usesSystemColors, isTrue);

    await provider.setAccentColor(config.AccentColorOption.orchid);
    expect(provider.colorSource, config.AppColorSource.preset);
    expect(provider.accentId, config.AccentColorOption.orchid.id);

    await provider.setPaletteStrategy(config.AppPaletteStrategy.expressive);
    final expressivePrimary = provider.lightTheme.colorScheme.primary;
    await provider.setPaletteStrategy(config.AppPaletteStrategy.tonalSpot);
    expect(provider.paletteStrategy, config.AppPaletteStrategy.tonalSpot);
    expect(provider.schemeVariant, DynamicSchemeVariant.tonalSpot);
    expect(provider.lightTheme.colorScheme.primary, isNot(expressivePrimary));
    expect(provider.seedColor, config.AccentColorOption.orchid.seedColor);

    const custom = Color(0xFF7A3DF0);
    await provider.setCustomSeedColor(custom);
    expect(provider.colorSource, config.AppColorSource.custom);
    expect(provider.seedColor, custom);
    expect(provider.accentId, isNull);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('appearance_color_source'), 'custom');
    expect(preferences.getInt('appearance_seed_color'), custom.toARGB32());
    expect(preferences.getString('appearance_palette_strategy'), 'tonalSpot');

    final restored = ThemeProvider();
    addTearDown(restored.dispose);
    await tester.pump();
    expect(restored.paletteStrategy, config.AppPaletteStrategy.tonalSpot);
  });

  testWidgets('appearance remains usable at 200 percent text scale', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final provider = ThemeProvider();
    final appIconProvider = AppIconProvider();
    addTearDown(provider.dispose);
    addTearDown(appIconProvider.dispose);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider.value(value: appIconProvider),
        ],
        child: MaterialApp(
          theme: provider.lightTheme,
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(360, 900),
              textScaler: TextScaler.linear(2),
            ),
            child: AppearanceScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Theme'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('OLED black'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Palette style'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Tonal spot'), findsWidgets);
    expect(find.text('Expressive'), findsWidgets);
    final tonal = find.byKey(const ValueKey('palette-style-tonalSpot'));
    final expressive = find.byKey(const ValueKey('palette-style-expressive'));
    expect(tester.getTopLeft(tonal).dy, tester.getTopLeft(expressive).dy);
    expect(
      tester.getTopLeft(tonal).dx,
      lessThan(tester.getTopLeft(expressive).dx),
    );
    expect(
      find.descendant(of: tonal, matching: find.text('Buttons')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tonal, matching: find.text('Surfaces')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        RegExp(r'System.*Follows your device', dotAll: true),
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Device colors'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Device colors'), findsOneWidget);
    final colorTiles = [
      'indigo',
      'ocean',
      'ember',
    ].map((id) => find.byKey(ValueKey('color-theme-$id'))).toList();
    expect(
      tester.getTopLeft(colorTiles[0]).dy,
      tester.getTopLeft(colorTiles[1]).dy,
    );
    expect(
      tester.getTopLeft(colorTiles[1]).dy,
      tester.getTopLeft(colorTiles[2]).dy,
    );
    final selectedTile = tester.widget<AppSurface>(
      find.byKey(const ValueKey('color-theme-orchid')),
    );
    expect(selectedTile.border, BorderSide.none);
    expect(
      selectedTile.color,
      provider.lightTheme.colorScheme.primaryContainer,
    );
    await tester.scrollUntilVisible(
      find.text('Custom color'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Custom color'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('App icon'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('app-icon-three_d')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-icon-ocean')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-icon-red')), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('app icon picker adds columns without resizing artwork', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final provider = ThemeProvider();
    final appIconProvider = AppIconProvider();
    addTearDown(provider.dispose);
    addTearDown(appIconProvider.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: provider),
          ChangeNotifierProvider.value(value: appIconProvider),
        ],
        child: MaterialApp(
          theme: provider.lightTheme,
          home: const MediaQuery(
            data: MediaQueryData(size: Size(390, 900)),
            child: AppearanceScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('app-icon-three_d')),
      260,
      scrollable: find.byType(Scrollable).first,
    );

    final firstRowY = tester
        .getCenter(find.byKey(const ValueKey('app-icon-burgundy')))
        .dy;
    for (final id in ['three_d', 'purple', 'multicolor']) {
      expect(
        tester.getCenter(find.byKey(ValueKey('app-icon-$id'))).dy,
        closeTo(firstRowY, 0.1),
      );
    }
    expect(
      tester.getCenter(find.byKey(const ValueKey('app-icon-ocean'))).dy,
      greaterThan(firstRowY),
    );

    final artwork = tester.widget<AppIconArtwork>(
      find.descendant(
        of: find.byKey(const ValueKey('app-icon-three_d')),
        matching: find.byType(AppIconArtwork),
      ),
    );
    expect(artwork.size, 56);
  });

  testWidgets('reduced motion resolves shared transitions to zero', (
    tester,
  ) async {
    Duration? resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              resolved = AppMotion.resolve(context, AppMotion.emphasized);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(resolved, Duration.zero);
  });
}

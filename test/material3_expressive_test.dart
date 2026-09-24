import 'package:cards_wallet/models/theme_config.dart' as config;
import 'package:cards_wallet/providers/theme_provider.dart';
import 'package:cards_wallet/providers/app_icon_provider.dart';
import 'package:cards_wallet/screens/appearance_screen.dart';
import 'package:cards_wallet/theme/app_colors.dart';
import 'package:cards_wallet/theme/app_motion.dart';
import 'package:cards_wallet/widgets/app_icon_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    expect(provider.paletteStrategy, config.AppPaletteStrategy.expressive);
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
        .getCenter(find.byKey(const ValueKey('app-icon-three_d')))
        .dy;
    for (final id in ['purple', 'multicolor', 'ocean']) {
      expect(
        tester.getCenter(find.byKey(ValueKey('app-icon-$id'))).dy,
        closeTo(firstRowY, 0.1),
      );
    }
    expect(
      tester.getCenter(find.byKey(const ValueKey('app-icon-emerald'))).dy,
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

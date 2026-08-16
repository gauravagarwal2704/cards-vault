import 'package:cards_wallet/models/theme_config.dart' as config;
import 'package:cards_wallet/providers/theme_provider.dart';
import 'package:cards_wallet/screens/appearance_screen.dart';
import 'package:cards_wallet/theme/app_colors.dart';
import 'package:cards_wallet/theme/app_motion.dart';
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

    const custom = Color(0xFF7A3DF0);
    await provider.setCustomSeedColor(custom);
    expect(provider.colorSource, config.AppColorSource.custom);
    expect(provider.seedColor, custom);
    expect(provider.accentId, isNull);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('appearance_color_source'), 'custom');
    expect(preferences.getInt('appearance_seed_color'), custom.toARGB32());
  });

  testWidgets('appearance remains usable at 200 percent text scale', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final provider = ThemeProvider();
    addTearDown(provider.dispose);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
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

    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('OLED black'), findsOneWidget);
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
    expect(tester.takeException(), isNull);
    semantics.dispose();
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

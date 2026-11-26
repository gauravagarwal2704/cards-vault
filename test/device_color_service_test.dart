import 'package:cards_wallet/models/theme_config.dart' as config;
import 'package:cards_wallet/providers/theme_provider.dart';
import 'package:cards_wallet/services/device_color_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _palette(double hue, {bool withRoles = false}) => {
  for (final family in [
    'accent1',
    'accent2',
    'accent3',
    'neutral1',
    'neutral2',
  ])
    family: {
      for (final tone in [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 100])
        '$tone': HSLColor.fromAHSL(
          1,
          hue,
          family.startsWith('neutral') ? 0.08 : 0.3,
          tone / 100,
        ).toColor().toARGB32(),
    },
  if (withRoles) 'light': {'primary': 0xFF345678, 'surface': 0xFFFAF8F0},
  if (withRoles) 'dark': {'primary': 0xFFABCDEF, 'surface': 0xFF141210},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cards_wallet/appearance');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets(
    'first-time default is Tonal Spot while saved appearance styles survive',
    (tester) async {
      final fresh = ThemeProvider();
      addTearDown(fresh.dispose);
      await tester.pump();
      expect(fresh.paletteStrategy, config.AppPaletteStrategy.tonalSpot);
      expect(fresh.seedColor, config.AccentColorOption.orchid.seedColor);
      expect(fresh.accentId, config.AccentColorOption.orchid.id);
      SharedPreferences.setMockInitialValues({
        'appearance_seed_color': config.AccentColorOption.orchid.seedColor
            .toARGB32(),
      });
      final existing = ThemeProvider();
      addTearDown(existing.dispose);
      await tester.pump();
      expect(existing.paletteStrategy, config.AppPaletteStrategy.expressive);
      await existing.setPaletteStrategy(config.AppPaletteStrategy.tonalSpot);
      final restored = ThemeProvider();
      addTearDown(restored.dispose);
      await tester.pump();
      expect(restored.paletteStrategy, config.AppPaletteStrategy.tonalSpot);
    },
  );

  testWidgets(
    'device palettes replace the prior preset and refresh after resume',
    (tester) async {
      var palette = _palette(140);
      var reads = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        reads++;
        expectSync(call.method, 'getSystemPalette');
        return palette;
      });
      final provider = ThemeProvider();
      addTearDown(provider.dispose);
      await tester.pump();
      await provider.setAccentColor(config.AccentColorOption.orchid);
      final preset = provider.lightTheme.colorScheme.primary;
      await provider.useSystemColorSource();
      expect(provider.hasDeviceColors, isTrue);
      expect(
        provider.lightTheme.colorScheme.primary.toARGB32(),
        palette['accent1']['40'],
      );
      expect(provider.lightTheme.colorScheme.primary, isNot(preset));
      expect(
        provider.darkTheme.colorScheme.primary.toARGB32(),
        palette['accent1']['80'],
      );
      expect(
        provider.lightTheme.filledButtonTheme.style!.backgroundColor!.resolve(
          {},
        ),
        provider.lightTheme.colorScheme.primary,
      );
      await provider.setPaletteStrategy(config.AppPaletteStrategy.expressive);
      expect(
        provider.lightTheme.colorScheme.primary.toARGB32(),
        palette['accent1']['40'],
      );

      palette = _palette(220, withRoles: true);
      provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(provider.lightTheme.colorScheme.primary.toARGB32(), 0xFF345678);
      expect(provider.darkTheme.colorScheme.primary.toARGB32(), 0xFFABCDEF);
      expect(
        provider.lightTheme.scaffoldBackgroundColor.toARGB32(),
        0xFFFAF8F0,
      );
      expect(provider.oledTheme.colorScheme.primary.toARGB32(), 0xFFABCDEF);
      expect(provider.oledTheme.colorScheme.surface, Colors.black);
      final restored = ThemeProvider();
      addTearDown(restored.dispose);
      for (var i = 0; i < 10 && !restored.isInitialized; i++) {
        await tester.pump();
      }
      expect(restored.isInitialized, isTrue);
      expect(restored.usesSystemColors, isTrue);
      expect(reads, greaterThanOrEqualTo(3));
      expect(restored.hasDeviceColors, isTrue);
      expect(restored.lightTheme.colorScheme.primary.toARGB32(), 0xFF345678);

      await provider.setAccentColor(config.AccentColorOption.orchid);
      await provider.setPaletteStrategy(config.AppPaletteStrategy.tonalSpot);
      expect(provider.lightTheme.colorScheme.primary, preset);
    },
  );

  testWidgets(
    'unsupported device palettes use a stable fallback instead of the last preset',
    (tester) async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      final provider = ThemeProvider();
      addTearDown(provider.dispose);
      await tester.pump();
      final fallback = provider.lightTheme.colorScheme;
      await provider.setAccentColor(config.AccentColorOption.ember);
      await provider.useSystemColorSource();
      expect(provider.hasDeviceColors, isFalse);
      expect(provider.lightTheme.colorScheme, fallback);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'palette_unavailable'),
      );
      expect(await DeviceColorService.load(), isNull);
    },
  );

  testWidgets(
    'new soft presets are selectable and persist with Material tonal surfaces',
    (tester) async {
      final provider = ThemeProvider();
      addTearDown(provider.dispose);
      await tester.pump();
      for (final option in config.AccentColorOption.featuredPresets.skip(6)) {
        await provider.setAccentColor(option);
        expect(provider.accentId, option.id);
        expect(
          provider.lightTheme.colorScheme.primaryContainer.computeLuminance(),
          greaterThan(0.65),
        );
        final restored = ThemeProvider();
        await tester.pump();
        expect(restored.accentId, option.id);
        expect(restored.seedColor, option.seedColor);
        restored.dispose();
      }
      expect(config.AccentColorOption.featuredPresets.length, 14);
    },
  );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/theme_config.dart' as config;
import '../models/app_icon_option.dart';
import '../providers/app_icon_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_motion.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_design_system.dart';
import '../widgets/app_icon_artwork.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ThemeProvider>();
    final appIconProvider = context.watch<AppIconProvider>();
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = AppSpacing.pageHorizontal(width);

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 40),
        children: [
          _AppearancePreview(provider: provider),
          const SizedBox(height: AppSpacing.xxl),
          AppSection(
            title: 'Theme',
            description: 'Choose how CardVault responds to your display.',
            child: _ModeGrid(provider: provider),
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppSection(
            title: 'Palette style',
            description: 'Compare a focused palette with a more colorful one. Device colors still follow your system.',
            child: _PaletteStrategySelector(provider: provider),
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppSection(
            title: 'Color theme',
            description: 'Changes buttons, highlights, and tonal surfaces.',
            child: Column(
              children: [
                _SystemColorTile(provider: provider),
                const SizedBox(height: AppSpacing.sm),
                _PaletteGrid(provider: provider),
                const SizedBox(height: AppSpacing.sm),
                _CustomColorTile(provider: provider),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppSection(
            title: 'App icon',
            description:
                'Changes the launcher, splash, and CardVault branding.',
            child: _AppIconGrid(provider: appIconProvider),
          ),
        ],
      ),
    );
  }
}

class _AppIconGrid extends StatelessWidget {
  const _AppIconGrid({required this.provider});

  final AppIconProvider provider;

  Future<void> _select(BuildContext context, AppIconOption option) async {
    final error = await provider.selectIcon(option);
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(error ?? '${option.label} app icon selected'),
        backgroundColor: error == null
            ? null
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minimumSlotWidth = 68.0;
        const gap = AppSpacing.xxs;
        final columns =
            ((constraints.maxWidth + gap) / (minimumSlotWidth + gap))
                .floor()
                .clamp(1, AppIconCatalog.options.length);
        final width = (constraints.maxWidth - (gap * (columns - 1))) / columns;
        final scaledLabelHeight =
            MediaQuery.textScalerOf(context).scale(12) * 1.35;
        final height = 82 + scaledLabelHeight;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final option in AppIconCatalog.options)
              SizedBox(
                width: width,
                height: height,
                child: _AppIconTile(
                  option: option,
                  selected: provider.selected.id == option.id,
                  enabled: !provider.isChanging,
                  onTap: () => _select(context, option),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AppIconTile extends StatelessWidget {
  const _AppIconTile({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final AppIconOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelColor = selected ? scheme.primary : scheme.onSurface;
    return Semantics(
      key: ValueKey('app-icon-${option.id}'),
      button: true,
      selected: selected,
      enabled: enabled,
      label: '${option.label} app icon, ${option.description}',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AppIconArtwork(
                        option: option,
                        size: 56,
                        borderRadius: 15,
                      ),
                      if (selected)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: scheme.surface,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: scheme.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTypography.caption(color: labelColor)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppearancePreview extends StatelessWidget {
  const _AppearancePreview({required this.provider});

  final ThemeProvider provider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Live theme preview',
      image: true,
      child: AnimatedContainer(
        duration: AppMotion.resolve(context, AppMotion.standard),
        curve: AppMotion.standardCurve,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: ShapeDecoration(
          color: scheme.surfaceContainerLow,
          shape: AppShapes.extraLarge,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: AspectRatio(
                aspectRatio: 1.586,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [scheme.primary, scheme.tertiary],
                    ),
                    shape: AppShapes.large,
                    shadows: [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.shield_rounded,
                              color: scheme.onPrimary,
                              size: 20,
                            ),
                            const Spacer(),
                            Icon(
                              Icons.contactless_rounded,
                              color: scheme.onPrimary.withValues(alpha: 0.8),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Container(
                          width: 84,
                          height: 8,
                          decoration: ShapeDecoration(
                            color: scheme.onPrimary.withValues(alpha: 0.88),
                            shape: AppShapes.pill,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          '••••  2048',
                          style: AppTypography.mono(
                            color: scheme.onPrimary,
                            fontSize: 13,
                            letterSpacing: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CardVault',
                    style: AppTypography.title(color: scheme.onSurface),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    provider.usesSystemColors
                        ? 'Device colors'
                        : provider.isCustomColor
                        ? 'Custom palette'
                        : config.AccentColorOption.findById(
                                provider.accentId ?? '',
                              )?.name ??
                              'CardVault palette',
                    style: AppTypography.caption(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    provider.paletteStrategy.label,
                    style: AppTypography.caption(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      _PreviewDot(color: scheme.primary),
                      _PreviewDot(color: scheme.secondary),
                      _PreviewDot(color: scheme.tertiary),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewDot extends StatelessWidget {
  const _PreviewDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(right: 5),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _PaletteStrategySelector extends StatelessWidget {
  const _PaletteStrategySelector({required this.provider});

  final ThemeProvider provider;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final stacked = constraints.maxWidth < 430 || textScale >= 1.5;
        final cards = [
          for (final strategy in config.AppPaletteStrategy.values)
            _PaletteStrategyCard(
              strategy: strategy,
              selected: provider.paletteStrategy == strategy,
              seedColor: provider.seedColor,
              onTap: () => provider.setPaletteStrategy(strategy),
            ),
        ];

        if (stacked) {
          return Column(
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                cards[index],
                if (index != cards.length - 1)
                  const SizedBox(height: AppSpacing.sm),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards.first),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: cards.last),
          ],
        );
      },
    );
  }
}

class _PaletteStrategyCard extends StatelessWidget {
  const _PaletteStrategyCard({
    required this.strategy,
    required this.selected,
    required this.seedColor,
    required this.onTap,
  });

  final config.AppPaletteStrategy strategy;
  final bool selected;
  final Color seedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: scheme.brightness,
      dynamicSchemeVariant: strategy.schemeVariant,
    );

    return AppSurface(
      onTap: onTap,
      semanticLabel: '${strategy.label}. ${strategy.description}',
      selected: selected,
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      border: BorderSide(
        color: selected ? scheme.primary : scheme.outlineVariant,
        width: selected ? 2 : 1,
      ),
      shape: selected ? AppShapes.large : AppShapes.medium,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PreviewDot(color: preview.primary),
              _PreviewDot(color: preview.secondary),
              _PreviewDot(color: preview.tertiary),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            strategy.label,
            style: AppTypography.label(
              color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            strategy.description,
            style: AppTypography.caption(
              color: selected
                  ? scheme.onPrimaryContainer.withValues(alpha: 0.78)
                  : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeGrid extends StatelessWidget {
  const _ModeGrid({required this.provider});
  final ThemeProvider provider;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - AppSpacing.sm) / 2;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final mode in config.AppBrightnessMode.values)
              SizedBox(
                width: itemWidth,
                child: _ModeCard(
                  mode: mode,
                  selected: provider.brightnessMode == mode,
                  provider: provider,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.provider,
  });

  final config.AppBrightnessMode mode;
  final bool selected;
  final ThemeProvider provider;

  String get label => switch (mode) {
    config.AppBrightnessMode.system => 'System',
    config.AppBrightnessMode.light => 'Light',
    config.AppBrightnessMode.dark => 'Dark',
    config.AppBrightnessMode.amoled => 'OLED black',
  };

  String get description => switch (mode) {
    config.AppBrightnessMode.system => 'Follows your device',
    config.AppBrightnessMode.light => 'Bright surfaces',
    config.AppBrightnessMode.dark => 'Dim tonal surfaces',
    config.AppBrightnessMode.amoled => 'Pure black base',
  };

  IconData get icon => switch (mode) {
    config.AppBrightnessMode.system => Icons.brightness_auto_rounded,
    config.AppBrightnessMode.light => Icons.light_mode_rounded,
    config.AppBrightnessMode.dark => Icons.dark_mode_rounded,
    config.AppBrightnessMode.amoled => Icons.contrast_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final outer = Theme.of(context).colorScheme;
    final preview = switch (mode) {
      config.AppBrightnessMode.light => provider.lightTheme.colorScheme,
      config.AppBrightnessMode.dark => provider.darkTheme.colorScheme,
      config.AppBrightnessMode.amoled => provider.oledTheme.colorScheme,
      config.AppBrightnessMode.system => outer,
    };

    return AppSurface(
      onTap: () => provider.setBrightnessMode(mode),
      semanticLabel: '$label, $description',
      selected: selected,
      color: selected ? outer.primaryContainer : outer.surfaceContainerLow,
      border: BorderSide(
        color: selected ? outer.primary : outer.outlineVariant,
        width: selected ? 2 : 1,
      ),
      shape: selected ? AppShapes.large : AppShapes.medium,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: ShapeDecoration(
                  color: preview.surface,
                  shape: AppShapes.medium,
                ),
                child: Icon(icon, color: preview.primary),
              ),
              const Spacer(),
              AnimatedSwitcher(
                duration: AppMotion.resolve(context, AppMotion.quick),
                child: selected
                    ? Icon(
                        Icons.check_circle_rounded,
                        key: const ValueKey('selected'),
                        color: outer.onPrimaryContainer,
                      )
                    : const SizedBox(key: ValueKey('unselected'), width: 24),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            label,
            style: AppTypography.label(
              color: selected ? outer.onPrimaryContainer : outer.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption(
              color: selected
                  ? outer.onPrimaryContainer.withValues(alpha: 0.78)
                  : outer.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemColorTile extends StatelessWidget {
  const _SystemColorTile({required this.provider});
  final ThemeProvider provider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = provider.usesSystemColors;
    return AppSurface(
      onTap: provider.useSystemColorSource,
      semanticLabel: 'Device colors, uses wallpaper or system accent',
      selected: selected,
      color: selected ? scheme.secondaryContainer : scheme.surfaceContainerLow,
      border: BorderSide(
        color: selected ? scheme.secondary : scheme.outlineVariant,
        width: selected ? 2 : 1,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: ShapeDecoration(
              gradient: SweepGradient(
                colors: [
                  scheme.primary,
                  scheme.tertiary,
                  scheme.secondary,
                  scheme.primary,
                ],
              ),
              shape: AppShapes.medium,
            ),
            child: Icon(Icons.wallpaper_rounded, color: scheme.onPrimary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Device colors',
                  style: AppTypography.label(
                    color: selected
                        ? scheme.onSecondaryContainer
                        : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Uses your wallpaper or system accent when available',
                  style: AppTypography.caption(
                    color: selected
                        ? scheme.onSecondaryContainer.withValues(alpha: 0.78)
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            Icon(
              Icons.check_circle_rounded,
              color: scheme.onSecondaryContainer,
            ),
        ],
      ),
    );
  }
}

class _PaletteGrid extends StatelessWidget {
  const _PaletteGrid({required this.provider});
  final ThemeProvider provider;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - AppSpacing.xs) / 2;
        return Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final option in config.AccentColorOption.featuredPresets)
              SizedBox(
                width: width,
                child: _PaletteTile(
                  option: option,
                  schemeVariant: provider.schemeVariant,
                  selected:
                      provider.colorSource == config.AppColorSource.preset &&
                      provider.accentId == option.id,
                  onTap: () => provider.setAccentColor(option),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.option,
    required this.schemeVariant,
    required this.selected,
    required this.onTap,
  });
  final config.AccentColorOption option;
  final DynamicSchemeVariant schemeVariant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = ColorScheme.fromSeed(
      seedColor: option.seedColor,
      brightness: scheme.brightness,
      dynamicSchemeVariant: schemeVariant,
    );
    return AppSurface(
      onTap: onTap,
      semanticLabel: '${option.name} color palette',
      selected: selected,
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      shape: selected ? AppShapes.large : AppShapes.medium,
      border: BorderSide(
        color: selected ? scheme.primary : scheme.outlineVariant,
        width: selected ? 2 : 1,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 34,
            child: Stack(
              children: [
                _paletteDot(palette.primary, 0),
                _paletteDot(palette.secondary, 14),
                _paletteDot(palette.tertiary, 28),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              option.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.label(
                color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
            ),
          ),
          if (selected)
            Icon(
              Icons.check_rounded,
              size: 18,
              color: scheme.onPrimaryContainer,
            ),
        ],
      ),
    );
  }

  Widget _paletteDot(Color color, double left) => Positioned(
    left: left,
    child: Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
    ),
  );
}

class _CustomColorTile extends StatelessWidget {
  const _CustomColorTile({required this.provider});
  final ThemeProvider provider;

  Future<void> _openPicker(BuildContext context) async {
    final result = await showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomColorPicker(initialColor: provider.seedColor),
    );
    if (result != null) await provider.setCustomSeedColor(result);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = provider.isCustomColor;
    return AppSurface(
      onTap: () => _openPicker(context),
      semanticLabel: 'Create a custom color palette',
      selected: selected,
      color: selected ? scheme.tertiaryContainer : scheme.surfaceContainerLow,
      border: BorderSide(
        color: selected ? scheme.tertiary : scheme.outlineVariant,
        width: selected ? 2 : 1,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: ShapeDecoration(
              gradient: const SweepGradient(
                colors: [
                  Color(0xFFE53935),
                  Color(0xFFFDD835),
                  Color(0xFF43A047),
                  Color(0xFF1E88E5),
                  Color(0xFF8E24AA),
                  Color(0xFFE53935),
                ],
              ),
              shape: AppShapes.medium,
            ),
            child: const Icon(Icons.colorize_rounded, color: Colors.white),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Custom color',
                  style: AppTypography.label(
                    color: selected
                        ? scheme.onTertiaryContainer
                        : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Build an accessible palette from any seed color',
                  style: AppTypography.caption(
                    color: selected
                        ? scheme.onTertiaryContainer.withValues(alpha: 0.78)
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _CustomColorPicker extends StatefulWidget {
  const _CustomColorPicker({required this.initialColor});
  final Color initialColor;

  @override
  State<_CustomColorPicker> createState() => _CustomColorPickerState();
}

class _CustomColorPickerState extends State<_CustomColorPicker> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initialColor);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _hsv.toColor();
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Custom color',
              style: AppTypography.dialogTitle(color: scheme.onSurface),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'CardVault creates the supporting tones and readable foreground colors.',
              style: AppTypography.body(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xl),
            Center(
              child: AnimatedContainer(
                duration: AppMotion.resolve(context, AppMotion.quick),
                width: 88,
                height: 88,
                decoration: ShapeDecoration(
                  color: color,
                  shape: AppShapes.extraLarge.copyWith(
                    side: BorderSide(color: scheme.outlineVariant, width: 2),
                  ),
                ),
                child: Icon(
                  Icons.palette_rounded,
                  color:
                      ThemeData.estimateBrightnessForColor(color) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _HueSlider(
              value: _hsv.hue,
              onChanged: (value) => setState(() => _hsv = _hsv.withHue(value)),
            ),
            _LabeledSlider(
              label: 'Intensity',
              value: _hsv.saturation,
              activeColor: color,
              onChanged: (value) =>
                  setState(() => _hsv = _hsv.withSaturation(value)),
            ),
            _LabeledSlider(
              label: 'Brightness',
              value: _hsv.value.clamp(0.2, 1),
              min: 0.2,
              activeColor: color,
              onChanged: (value) =>
                  setState(() => _hsv = _hsv.withValue(value)),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, color),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.activeColor,
    this.min = 0,
  });
  final String label;
  final double value;
  final double min;
  final ValueChanged<double> onChanged;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.label(color: scheme.onSurfaceVariant)),
        Slider(
          value: value,
          min: min,
          max: 1,
          activeColor: activeColor,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hue', style: AppTypography.label(color: scheme.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.xs),
        LayoutBuilder(
          builder: (context, constraints) {
            return Semantics(
              slider: true,
              label: 'Custom color hue',
              value: '${value.round()} degrees',
              increasedValue: '${(value + 10).clamp(0, 360).round()} degrees',
              decreasedValue: '${(value - 10).clamp(0, 360).round()} degrees',
              onIncrease: () => onChanged((value + 10).clamp(0, 360)),
              onDecrease: () => onChanged((value - 10).clamp(0, 360)),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => onChanged(
                  (details.localPosition.dx / constraints.maxWidth * 360).clamp(
                    0,
                    360,
                  ),
                ),
                onHorizontalDragUpdate: (details) => onChanged(
                  (details.localPosition.dx / constraints.maxWidth * 360).clamp(
                    0,
                    360,
                  ),
                ),
                child: SizedBox(
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 18,
                        decoration: const ShapeDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFFFF0000),
                              Color(0xFFFFFF00),
                              Color(0xFF00FF00),
                              Color(0xFF00FFFF),
                              Color(0xFF0000FF),
                              Color(0xFFFF00FF),
                              Color(0xFFFF0000),
                            ],
                          ),
                          shape: AppShapes.pill,
                        ),
                      ),
                      Positioned(
                        left: (value / 360 * constraints.maxWidth - 11).clamp(
                          0,
                          constraints.maxWidth - 22,
                        ),
                        child: Container(
                          width: 22,
                          height: 32,
                          decoration: BoxDecoration(
                            color: HSVColor.fromAHSV(1, value, 1, 1).toColor(),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: scheme.surface, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: scheme.shadow.withValues(alpha: 0.25),
                                blurRadius: 5,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

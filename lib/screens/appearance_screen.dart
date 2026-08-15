import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/theme_config.dart' as config;
import '../providers/theme_provider.dart';
import '../theme/app_typography.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      backgroundColor: themeProvider.getBackgroundColor(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: themeProvider.getPrimaryTextColor(),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Appearance',
          style: AppTypography.appBarTitle(
            color: themeProvider.getPrimaryTextColor(),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Mode',
            style: AppTypography.sectionTitle(
              color: themeProvider.getPrimaryTextColor(),
            ),
          ),
          const SizedBox(height: 12),
          _ModeSelector(themeProvider: themeProvider),
          const SizedBox(height: 28),
          Text(
            'Accent color',
            style: AppTypography.sectionTitle(
              color: themeProvider.getPrimaryTextColor(),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Applies to Light, Dark, and AMOLED',
            style: AppTypography.caption(
              color: themeProvider.getSecondaryTextColor(),
            ),
          ),
          const SizedBox(height: 16),
          _AccentColorRow(themeProvider: themeProvider),
        ],
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.themeProvider});

  final ThemeProvider themeProvider;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: themeProvider.getCardColor(),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          for (final mode in config.AppBrightnessMode.values)
            Expanded(
              child: _ModeChip(
                mode: mode,
                selected: themeProvider.brightnessMode == mode,
                themeProvider: themeProvider,
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.mode,
    required this.selected,
    required this.themeProvider,
  });

  final config.AppBrightnessMode mode;
  final bool selected;
  final ThemeProvider themeProvider;

  String get _label {
    switch (mode) {
      case config.AppBrightnessMode.light:
        return 'Light';
      case config.AppBrightnessMode.dark:
        return 'Dark';
      case config.AppBrightnessMode.amoled:
        return 'AMOLED';
    }
  }

  IconData get _icon {
    switch (mode) {
      case config.AppBrightnessMode.light:
        return Icons.light_mode_outlined;
      case config.AppBrightnessMode.dark:
        return Icons.dark_mode_outlined;
      case config.AppBrightnessMode.amoled:
        return Icons.contrast_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = themeProvider.seedColor;
    final onAccent = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final textColor = selected
        ? onAccent
        : themeProvider.getPrimaryTextColor();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: selected ? accent : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => themeProvider.setBrightnessMode(mode),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                Icon(_icon, size: 20, color: textColor),
                const SizedBox(height: 6),
                Text(
                  _label,
                  style: AppTypography.caption(color: textColor).copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccentColorRow extends StatelessWidget {
  const _AccentColorRow({required this.themeProvider});

  final ThemeProvider themeProvider;

  Future<void> _openCustomPicker(BuildContext context) async {
    final result = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => _CustomColorPickerDialog(
        initialColor: themeProvider.seedColor,
      ),
    );
    if (result != null) {
      await themeProvider.setCustomSeedColor(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: themeProvider.getCardColor(),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (final option in config.AccentColorOption.presets)
            _ColorCircle(
              color: option.seedColor,
              selected: !themeProvider.isCustomColor &&
                  themeProvider.accentId == option.id,
              onTap: () => themeProvider.setAccentColor(option),
              semanticLabel: option.name,
            ),
          _CustomColorCircle(
            color: themeProvider.seedColor,
            selected: themeProvider.isCustomColor,
            onTap: () => _openCustomPicker(context),
          ),
        ],
      ),
    );
  }
}

class _ColorCircle extends StatelessWidget {
  const _ColorCircle({
    required this.color,
    required this.selected,
    required this.onTap,
    required this.semanticLabel,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: selected ? Colors.white : Colors.white24,
              width: selected ? 3 : 1.5,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withOpacity(0.45),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: selected
              ? const Icon(Icons.check, size: 18, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _CustomColorCircle extends StatelessWidget {
  const _CustomColorCircle({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Custom color',
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [
                color,
                HSVColor.fromAHSV(1, 0, 0.85, 1).toColor(),
                HSVColor.fromAHSV(1, 60, 0.85, 1).toColor(),
                HSVColor.fromAHSV(1, 120, 0.85, 1).toColor(),
                HSVColor.fromAHSV(1, 180, 0.85, 1).toColor(),
                HSVColor.fromAHSV(1, 240, 0.85, 1).toColor(),
                HSVColor.fromAHSV(1, 300, 0.85, 1).toColor(),
                color,
              ],
            ),
            border: Border.all(
              color: selected ? Colors.white : Colors.white24,
              width: selected ? 3 : 1.5,
            ),
          ),
          child: Icon(
            Icons.colorize,
            size: 16,
            color: selected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _CustomColorPickerDialog extends StatefulWidget {
  const _CustomColorPickerDialog({required this.initialColor});

  final Color initialColor;

  @override
  State<_CustomColorPickerDialog> createState() =>
      _CustomColorPickerDialogState();
}

class _CustomColorPickerDialogState extends State<_CustomColorPickerDialog> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(
        'Custom color',
        style: AppTypography.dialogTitle(color: scheme.onSurface),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: scheme.outlineVariant, width: 2),
            ),
          ),
          const SizedBox(height: 20),
          _HueSlider(
            value: _hsv.hue,
            onChanged: (hue) => setState(() {
              _hsv = _hsv.withHue(hue);
            }),
          ),
          const SizedBox(height: 8),
          Text(
            'Hue',
            style: AppTypography.caption(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Slider(
            value: _hsv.saturation,
            onChanged: (value) => setState(() {
              _hsv = _hsv.withSaturation(value);
            }),
            activeColor: color,
          ),
          Text(
            'Saturation',
            style: AppTypography.caption(color: scheme.onSurfaceVariant),
          ),
          Slider(
            value: _hsv.value.clamp(0.2, 1.0),
            min: 0.2,
            max: 1,
            onChanged: (value) => setState(() {
              _hsv = _hsv.withValue(value);
            }),
            activeColor: color,
          ),
          Text(
            'Brightness',
            style: AppTypography.caption(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, color),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _HueSlider extends StatelessWidget {
  const _HueSlider({
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  static final _hueColors = [
    for (var i = 0; i <= 6; i++)
      HSVColor.fromAHSV(1, (i * 60) % 360, 1, 1).toColor(),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Center(
              child: Container(
                height: 14,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(colors: _hueColors),
                ),
              ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 0,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: HSVColor.fromAHSV(1, value, 1, 1).toColor(),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: value,
              max: 359,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

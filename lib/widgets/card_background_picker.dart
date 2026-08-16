import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/card_designs.dart';
import '../theme/app_typography.dart';
import 'card_background_surface.dart';

enum CardBackgroundMode { catalog, customGradient, customImage }

class CardBackgroundPicker extends StatelessWidget {
  final CardBackgroundMode mode;
  final CardDesignStyle selectedStyle;
  final CardDesign? selectedDesign;
  final Color gradientStart;
  final Color gradientEnd;
  final double gradientAngle;
  final String? customImagePath;
  final double backgroundImageBlur;
  final ValueChanged<CardBackgroundMode> onModeChanged;
  final ValueChanged<CardDesignStyle> onStyleChanged;
  final ValueChanged<CardDesign> onDesignChanged;
  final void Function(Color start, Color end) onGradientChanged;
  final ValueChanged<double> onGradientAngleChanged;
  final ValueChanged<String?> onCustomImageChanged;
  final ValueChanged<double> onBackgroundImageBlurChanged;

  const CardBackgroundPicker({
    super.key,
    required this.mode,
    required this.selectedStyle,
    required this.selectedDesign,
    required this.gradientStart,
    required this.gradientEnd,
    required this.gradientAngle,
    required this.customImagePath,
    required this.backgroundImageBlur,
    required this.onModeChanged,
    required this.onStyleChanged,
    required this.onDesignChanged,
    required this.onGradientChanged,
    required this.onGradientAngleChanged,
    required this.onCustomImageChanged,
    required this.onBackgroundImageBlurChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildModeSelector(context),
        const SizedBox(height: 14),
        switch (mode) {
          CardBackgroundMode.catalog => _buildCatalog(context),
          CardBackgroundMode.customGradient => _buildGradientPicker(context),
          CardBackgroundMode.customImage => _buildImagePicker(context),
        },
        if (_supportsImageBlur) ...[
          const SizedBox(height: 14),
          _buildImageBlurControl(context),
        ],
      ],
    );
  }

  bool get _supportsImageBlur =>
      mode == CardBackgroundMode.customImage ||
      (mode == CardBackgroundMode.catalog &&
          selectedStyle == CardDesignStyle.image);

  Widget _buildModeSelector(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _modeChip(
            context,
            CardBackgroundMode.catalog,
            Icons.auto_awesome_mosaic_outlined,
            'Designs',
          ),
          _modeChip(
            context,
            CardBackgroundMode.customGradient,
            Icons.gradient,
            'Gradient',
          ),
          _modeChip(
            context,
            CardBackgroundMode.customImage,
            Icons.add_photo_alternate_outlined,
            'Custom image',
          ),
        ],
      ),
    );
  }

  Widget _modeChip(
    BuildContext context,
    CardBackgroundMode value,
    IconData icon,
    String label,
  ) {
    final colors = Theme.of(context).colorScheme;
    final selected = mode == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) => onModeChanged(value),
        avatar: Icon(
          icon,
          size: 18,
          color: selected ? colors.onPrimary : colors.onSurfaceVariant,
        ),
        label: Text(label),
        labelStyle: AppTypography.label(
          color: selected ? colors.onPrimary : colors.onSurface,
        ),
        selectedColor: colors.primary,
        backgroundColor: colors.surface,
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
        ),
        showCheckmark: false,
      ),
    );
  }

  Widget _buildCatalog(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final designs = CardDesigns.getByStyle(selectedStyle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: CardDesignStyle.values.map((style) {
              final selected = selectedStyle == style;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  selected: selected,
                  onSelected: (_) => onStyleChanged(style),
                  label: Text(CardDesigns.getStyleName(style)),
                  labelStyle: AppTypography.label(
                    color: selected ? colors.onSecondary : colors.onSurface,
                  ),
                  selectedColor: colors.secondary,
                  backgroundColor: colors.surface,
                  side: BorderSide(
                    color: selected ? colors.secondary : colors.outlineVariant,
                  ),
                  showCheckmark: false,
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: designs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final design = designs[index];
              final selected = selectedDesign?.id == design.id;
              return Semantics(
                button: true,
                selected: selected,
                label: design.name,
                child: GestureDetector(
                  onTap: () => onDesignChanged(design),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 126,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? colors.primary
                            : colors.outlineVariant,
                        width: selected ? 3 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: CardBackgroundSurface(
                      design: design,
                      backgroundImageBlur: selected ? backgroundImageBlur : 0,
                      fallbackPrimaryColor: design.primaryColor,
                      fallbackSecondaryColor: design.secondaryColor,
                      borderRadius: BorderRadius.circular(10),
                      showShadow: false,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            design.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.label(
                              fontSize: 10,
                              color: design.foregroundColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGradientPicker(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose two colors',
            style: AppTypography.label(color: colors.onSurface),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _colorButton(
                  context,
                  label: 'Start',
                  color: gradientStart,
                  onChanged: (color) => onGradientChanged(color, gradientEnd),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _colorButton(
                  context,
                  label: 'End',
                  color: gradientEnd,
                  onChanged: (color) => onGradientChanged(gradientStart, color),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Swap colors',
                onPressed: () => onGradientChanged(gradientEnd, gradientStart),
                icon: const Icon(Icons.swap_horiz),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Angle',
                style: AppTypography.caption(color: colors.onSurfaceVariant),
              ),
              Expanded(
                child: Slider(
                  value: gradientAngle.clamp(0, 360),
                  min: 0,
                  max: 360,
                  divisions: 24,
                  label: '${gradientAngle.round()}°',
                  onChanged: onGradientAngleChanged,
                ),
              ),
              SizedBox(
                width: 42,
                child: Text(
                  '${gradientAngle.round()}°',
                  textAlign: TextAlign.end,
                  style: AppTypography.caption(color: colors.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _colorButton(
    BuildContext context, {
    required String label,
    required Color color,
    required ValueChanged<Color> onChanged,
  }) {
    final colors = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: () async {
        final picked = await _showColorPicker(context, color);
        if (picked != null) onChanged(picked);
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        side: BorderSide(color: colors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: colors.outlineVariant),
            ),
          ),
          const SizedBox(width: 9),
          Text(label, style: AppTypography.label(color: colors.onSurface)),
        ],
      ),
    );
  }

  Widget _buildImagePicker(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final path = customImagePath;
    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (path != null && path.isNotEmpty)
            Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          if (path != null && path.isNotEmpty)
            const DecoratedBox(
              decoration: BoxDecoration(color: Color(0x55000000)),
            ),
          Center(
            child: FilledButton.icon(
              onPressed: () => _chooseImage(context),
              icon: Icon(
                path == null ? Icons.add_photo_alternate_outlined : Icons.edit,
              ),
              label: Text(path == null ? 'Choose an image' : 'Replace image'),
            ),
          ),
          if (path != null && path.isNotEmpty)
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                tooltip: 'Remove image',
                onPressed: () => onCustomImageChanged(null),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageBlurControl(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final blur = backgroundImageBlur.clamp(0.0, 12.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.blur_on, color: colors.onSurfaceVariant, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Background blur',
                  style: AppTypography.label(color: colors.onSurface),
                ),
                Text(
                  blur == 0 ? 'Off' : '${blur.round()} of 12',
                  style: AppTypography.caption(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 150,
            child: Slider(
              value: blur,
              min: 0,
              max: 12,
              divisions: 12,
              label: blur == 0 ? 'Off' : blur.round().toString(),
              onChanged: onBackgroundImageBlurChanged,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseImage(BuildContext context) async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        imageQuality: 90,
      );
      if (image != null) onCustomImageChanged(image.path);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the image picker: $error')),
      );
    }
  }

  Future<Color?> _showColorPicker(BuildContext context, Color initialColor) {
    var hsv = HSVColor.fromColor(initialColor);
    const presets = <Color>[
      Color(0xFF0F172A),
      Color(0xFF2563EB),
      Color(0xFF06B6D4),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFFEF4444),
      Color(0xFFEC4899),
      Color(0xFF8B5CF6),
    ];
    return showDialog<Color>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final current = hsv.toColor();
          return AlertDialog(
            title: const Text('Pick a color'),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: current,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presets.map((preset) {
                      return GestureDetector(
                        onTap: () => setDialogState(
                          () => hsv = HSVColor.fromColor(preset),
                        ),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: preset,
                            shape: BoxShape.circle,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  _hsvSlider(
                    label: 'Hue',
                    value: hsv.hue,
                    max: 360,
                    onChanged: (value) =>
                        setDialogState(() => hsv = hsv.withHue(value)),
                  ),
                  _hsvSlider(
                    label: 'Saturation',
                    value: hsv.saturation,
                    max: 1,
                    onChanged: (value) =>
                        setDialogState(() => hsv = hsv.withSaturation(value)),
                  ),
                  _hsvSlider(
                    label: 'Brightness',
                    value: hsv.value,
                    max: 1,
                    onChanged: (value) =>
                        setDialogState(() => hsv = hsv.withValue(value)),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, current),
                child: const Text('Use color'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _hsvSlider({
    required String label,
    required double value,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: Slider(value: value, min: 0, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}

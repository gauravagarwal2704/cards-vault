import 'package:flutter/material.dart';

/// Foreground tones used on cards. They deliberately avoid pure white and
/// pure black, which keeps the typography softer without sacrificing contrast.
abstract final class CardContrast {
  static const Color ivory = Color(0xFFF7F4ED);
  static const Color charcoal = Color(0xFF24262B);

  static Color bestForeground(Iterable<Color> backgrounds) {
    final colors = backgrounds.toList(growable: false);
    if (colors.isEmpty) return ivory;

    final ivoryScore = colors
        .map((color) => ratio(ivory, color))
        .reduce((a, b) => a < b ? a : b);
    final charcoalScore = colors
        .map((color) => ratio(charcoal, color))
        .reduce((a, b) => a < b ? a : b);
    return charcoalScore > ivoryScore ? charcoal : ivory;
  }

  static bool needsScrim(Color foreground, Iterable<Color> backgrounds) {
    return backgrounds.any((color) => ratio(foreground, color) < 4.5);
  }

  static double ratio(Color foreground, Color background) {
    final foregroundLuminance = foreground.computeLuminance();
    final backgroundLuminance = background.computeLuminance();
    final lighter = foregroundLuminance > backgroundLuminance
        ? foregroundLuminance
        : backgroundLuminance;
    final darker = foregroundLuminance > backgroundLuminance
        ? backgroundLuminance
        : foregroundLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }

  static Color secondary(Color foreground) =>
      foreground.withValues(alpha: 0.74);

  static Color tertiary(Color foreground) => foreground.withValues(alpha: 0.58);
}

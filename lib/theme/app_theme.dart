import 'package:flutter/material.dart';
import '../models/theme_config.dart' as config;
import 'app_typography.dart';

class AppTheme {
  static ThemeData build({
    required config.AppBrightnessMode brightnessMode,
    required Color seedColor,
    DynamicSchemeVariant schemeVariant = DynamicSchemeVariant.expressive,
  }) {
    final isAmoled = brightnessMode == config.AppBrightnessMode.amoled;
    final brightness = brightnessMode == config.AppBrightnessMode.light
        ? Brightness.light
        : Brightness.dark;

    var colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: schemeVariant,
    );

    if (isAmoled) {
      colorScheme = colorScheme.copyWith(
        surface: const Color(0xFF000000),
        surfaceDim: const Color(0xFF000000),
        surfaceBright: const Color(0xFF1A1A1A),
        surfaceContainerLowest: const Color(0xFF000000),
        surfaceContainerLow: const Color(0xFF0A0A0A),
        surfaceContainer: const Color(0xFF121212),
        surfaceContainerHigh: const Color(0xFF1A1A1A),
        surfaceContainerHighest: const Color(0xFF242424),
      );
    }

    final scaffoldBackground =
        isAmoled ? const Color(0xFF000000) : colorScheme.surface;

    final cardColor = colorScheme.surfaceContainerHigh;
    final primaryText = colorScheme.onSurface;
    final secondaryText = colorScheme.onSurfaceVariant;
    final textTheme = AppTypography.textTheme(
      primary: primaryText,
      secondary: secondaryText,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
      fontFamily: AppTypography.fontFamily,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      cardColor: cardColor,
      dividerColor: colorScheme.outlineVariant,
      iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: primaryText,
        titleTextStyle: AppTypography.appBarTitle(color: primaryText),
        iconTheme: IconThemeData(color: primaryText),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          textStyle: AppTypography.button(),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          textStyle: AppTypography.button(),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: AppTypography.button(fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outline),
          textStyle: AppTypography.button(fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        labelStyle: AppTypography.label(color: secondaryText),
        hintStyle: AppTypography.body(color: secondaryText.withOpacity(0.7)),
        helperStyle: AppTypography.caption(color: secondaryText),
        errorStyle: AppTypography.caption(color: colorScheme.error),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle:
            AppTypography.body(color: colorScheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.dialogTitle(color: primaryText),
        contentTextStyle: AppTypography.body(color: secondaryText),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        titleTextStyle: AppTypography.listItem(color: primaryText),
        subtitleTextStyle: AppTypography.caption(color: secondaryText),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onPrimary;
          }
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return colorScheme.outline;
        }),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary.withOpacity(0.12);
          }
          return colorScheme.onSurface.withOpacity(0.08);
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(colorScheme.onPrimary),
        side: BorderSide(color: colorScheme.outline, width: 2),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        circularTrackColor: colorScheme.primaryContainer,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.secondaryContainer,
        labelStyle: AppTypography.caption(color: colorScheme.onSurface),
        secondaryLabelStyle:
            AppTypography.caption(color: colorScheme.onSecondaryContainer),
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
    );
  }
}

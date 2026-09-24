import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/theme_config.dart' as config;
import 'app_colors.dart';
import 'app_shapes.dart';
import 'app_typography.dart';
import 'app_motion.dart';

class AppTheme {
  static ThemeData build({
    required config.AppBrightnessMode brightnessMode,
    required Color seedColor,
    DynamicSchemeVariant schemeVariant = DynamicSchemeVariant.expressive,
    bool useSystemColors = false,
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

    final scaffoldBackground = isAmoled
        ? const Color(0xFF000000)
        : colorScheme.surface;

    final cardColor = colorScheme.surfaceContainerHigh;
    final primaryText = colorScheme.onSurface;
    final secondaryText = colorScheme.onSurfaceVariant;
    final textTheme = AppTypography.textTheme(
      primary: primaryText,
      secondary: secondaryText,
    );
    final semanticColors = AppSemanticColors.from(colorScheme);
    final overlayStyle = systemOverlayStyle(
      brightness: colorScheme.brightness,
      navigationBarColor: scaffoldBackground,
    );

    return ThemeData(
      useMaterial3: true,
      useSystemColors: useSystemColors,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      extensions: [semanticColors],
      scaffoldBackgroundColor: scaffoldBackground,
      fontFamily: AppTypography.fontFamily,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CardVaultPageTransitionsBuilder(),
          TargetPlatform.iOS: CardVaultPageTransitionsBuilder(),
          TargetPlatform.macOS: CardVaultPageTransitionsBuilder(),
          TargetPlatform.windows: CardVaultPageTransitionsBuilder(),
          TargetPlatform.linux: CardVaultPageTransitionsBuilder(),
        },
      ),
      cardColor: cardColor,
      dividerColor: colorScheme.outlineVariant,
      iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: primaryText,
        titleTextStyle: AppTypography.appBarTitle(color: primaryText),
        iconTheme: IconThemeData(color: primaryText),
        systemOverlayStyle: overlayStyle,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: AppShapes.large,
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          textStyle: AppTypography.button(),
          minimumSize: const Size(64, 48),
          shape: AppShapes.pill,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          textStyle: AppTypography.button(),
          minimumSize: const Size(64, 48),
          shape: AppShapes.pill,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: AppTypography.button(fontSize: 14),
          minimumSize: const Size(48, 48),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outline),
          textStyle: AppTypography.button(fontSize: 14),
          minimumSize: const Size(64, 48),
          shape: AppShapes.pill,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 2,
        shape: AppShapes.large,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        labelStyle: AppTypography.label(color: secondaryText),
        hintStyle: AppTypography.body(
          color: secondaryText.withValues(alpha: 0.7),
        ),
        helperStyle: AppTypography.caption(color: secondaryText),
        errorStyle: AppTypography.caption(color: colorScheme.error),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppShapes.radiusMedium),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppShapes.radiusMedium),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppShapes.radiusMedium),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: AppTypography.body(
          color: colorScheme.onInverseSurface,
        ),
        behavior: SnackBarBehavior.floating,
        shape: AppShapes.medium,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.dialogTitle(color: primaryText),
        contentTextStyle: AppTypography.body(color: secondaryText),
        shape: AppShapes.extraLarge,
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
            return colorScheme.primary.withValues(alpha: 0.12);
          }
          return colorScheme.onSurface.withValues(alpha: 0.08);
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
        showCheckmark: false,
        labelStyle: AppTypography.caption(color: colorScheme.onSurface),
        secondaryLabelStyle: AppTypography.caption(
          color: colorScheme.onSecondaryContainer,
        ),
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: AppShapes.pill,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        modalBackgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: colorScheme.scrim.withValues(alpha: 0.42),
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppShapes.radiusExtraLarge),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: AppShapes.large,
        textStyle: AppTypography.body(color: primaryText),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: const WidgetStatePropertyAll(AppShapes.pill),
          textStyle: WidgetStatePropertyAll(AppTypography.label()),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? colorScheme.secondaryContainer
                : colorScheme.surfaceContainerLow;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant;
          }),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: AppShapes.pill,
        labelTextStyle: WidgetStatePropertyAll(
          AppTypography.caption(color: colorScheme.onSurface),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: AppShapes.pill,
        selectedIconTheme: IconThemeData(
          color: colorScheme.onSecondaryContainer,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.secondaryContainer,
        thumbColor: colorScheme.primary,
        overlayColor: colorScheme.primary.withValues(alpha: 0.12),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: ShapeDecoration(
          color: colorScheme.inverseSurface,
          shape: AppShapes.small,
        ),
        textStyle: AppTypography.caption(color: colorScheme.onInverseSurface),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
    );
  }

  static SystemUiOverlayStyle systemOverlayStyle({
    required Brightness brightness,
    required Color navigationBarColor,
  }) {
    final isDark = brightness == Brightness.dark;
    final iconBrightness = isDark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: navigationBarColor,
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarDividerColor: Colors.transparent,
    );
  }
}

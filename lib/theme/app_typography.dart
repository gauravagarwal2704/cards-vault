import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Outfit-based type scale. Prefer semantic helpers over raw sizes.
class AppTypography {
  AppTypography._();

  static const String fontFamily = 'Outfit';

  static TextStyle style({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
    FontStyle? fontStyle,
    TextDecoration? decoration,
    Color? decorationColor,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontStyle: fontStyle,
      decoration: decoration,
      decorationColor: decorationColor,
    );
  }

  /// Hero / brand lockup — home greeting
  static TextStyle display({Color? color, double? fontSize}) => style(
        fontSize: fontSize ?? 32,
        fontWeight: FontWeight.w700,
        height: 1.15,
        letterSpacing: -0.5,
        color: color,
      );

  /// Secondary display weight (e.g. "Cards" next to count)
  static TextStyle displayLight({Color? color, double? fontSize}) => style(
        fontSize: fontSize ?? 32,
        fontWeight: FontWeight.w400,
        height: 1.15,
        letterSpacing: -0.5,
        color: color,
      );

  /// Screen / page titles
  static TextStyle pageTitle({Color? color}) => style(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: -0.3,
        color: color,
      );

  /// App bar / sheet titles
  static TextStyle appBarTitle({Color? color}) => style(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: color,
      );

  /// Section headers
  static TextStyle sectionTitle({Color? color}) => style(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: color,
      );

  /// Dialog / bottom-sheet titles
  static TextStyle dialogTitle({Color? color}) => style(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: color,
      );

  /// Card / list primary titles
  static TextStyle title({Color? color, double? fontSize}) => style(
        fontSize: fontSize ?? 16,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: color,
      );

  /// Emphasized name on card face
  static TextStyle cardName({Color? color, double? fontSize}) => style(
        fontSize: fontSize ?? 14,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: 0.2,
        color: color,
      );

  /// Light secondary word on card face (e.g. "Debit")
  static TextStyle cardNameLight({Color? color, double? fontSize}) => style(
        fontSize: fontSize ?? 14,
        fontWeight: FontWeight.w300,
        height: 1.2,
        color: color,
      );

  /// List row primary text
  static TextStyle listItem({Color? color}) => style(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.35,
        color: color,
      );

  /// Supporting / secondary body
  static TextStyle subtitle({Color? color, double? fontSize}) => style(
        fontSize: fontSize ?? 14,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: color,
      );

  static TextStyle body({Color? color, double? fontSize, FontWeight? fontWeight}) =>
      style(
        fontSize: fontSize ?? 14,
        fontWeight: fontWeight ?? FontWeight.w400,
        height: 1.45,
        color: color,
      );

  static TextStyle bodyLarge({Color? color}) => style(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: color,
      );

  /// Form labels, chip text
  static TextStyle label({Color? color, double? fontSize}) => style(
        fontSize: fontSize ?? 13,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0.1,
        color: color,
      );

  /// Captions, helper text
  static TextStyle caption({Color? color, double? fontSize}) => style(
        fontSize: fontSize ?? 12,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: color,
      );

  /// Small metadata / badges
  static TextStyle overline({Color? color, double? fontSize}) => style(
        fontSize: fontSize ?? 10,
        fontWeight: FontWeight.w500,
        height: 1.2,
        letterSpacing: 0.4,
        color: color,
      );

  static TextStyle button({Color? color, double? fontSize}) => style(
        fontSize: fontSize ?? 15,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0.2,
        color: color,
      );

  /// Monospace for PAN / expiry / CVV
  static TextStyle mono({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w500,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.sourceCodePro(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextTheme textTheme({
    required Color primary,
    required Color secondary,
  }) {
    return TextTheme(
      displayLarge: display(color: primary),
      displayMedium: display(color: primary).copyWith(fontSize: 28),
      displaySmall: pageTitle(color: primary),
      headlineLarge: pageTitle(color: primary),
      headlineMedium: appBarTitle(color: primary),
      headlineSmall: sectionTitle(color: primary),
      titleLarge: title(color: primary),
      titleMedium: listItem(color: primary),
      titleSmall: style(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: bodyLarge(color: primary),
      bodyMedium: body(color: primary),
      bodySmall: caption(color: secondary),
      labelLarge: button(color: primary),
      labelMedium: label(color: secondary),
      labelSmall: overline(color: secondary),
    );
  }
}

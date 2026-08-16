import 'package:flutter/material.dart';

/// CardVault's expressive shape scale.
///
/// Repetition uses medium/large shapes while hero and transient surfaces get
/// the larger radii. Pills are reserved for compact controls and statuses.
class AppShapes {
  AppShapes._();

  static const radiusExtraSmall = 8.0;
  static const radiusSmall = 12.0;
  static const radiusMedium = 16.0;
  static const radiusLarge = 24.0;
  static const radiusExtraLarge = 32.0;

  static const extraSmall = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(radiusExtraSmall)),
  );
  static const small = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(radiusSmall)),
  );
  static const medium = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(radiusMedium)),
  );
  static const large = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(radiusLarge)),
  );
  static const extraLarge = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(radiusExtraLarge)),
  );
  static const pill = StadiumBorder();

  static BorderRadius get mediumRadius =>
      const BorderRadius.all(Radius.circular(radiusMedium));
  static BorderRadius get largeRadius =>
      const BorderRadius.all(Radius.circular(radiusLarge));
  static BorderRadius get extraLargeRadius =>
      const BorderRadius.all(Radius.circular(radiusExtraLarge));
  static BorderRadius get pillRadius =>
      const BorderRadius.all(Radius.circular(999));
}

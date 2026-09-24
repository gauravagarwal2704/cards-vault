import 'package:flutter/material.dart';

/// Semantic colors that Material's core [ColorScheme] does not provide.
///
/// These roles intentionally behave like Material color roles: every strong
/// color has an `on` color and every quieter container has a matching
/// foreground. Screens should use these roles instead of `Colors.green`,
/// `Colors.orange`, or one-off hex values.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.privacy,
    required this.onPrivacy,
    required this.privacyContainer,
    required this.onPrivacyContainer,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;
  final Color privacy;
  final Color onPrivacy;
  final Color privacyContainer;
  final Color onPrivacyContainer;

  factory AppSemanticColors.from(ColorScheme scheme) {
    ColorScheme roles(Color seed) => ColorScheme.fromSeed(
      seedColor: seed,
      brightness: scheme.brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );

    final success = roles(const Color(0xFF16834A));
    final warning = roles(const Color(0xFFB86A00));
    final info = roles(const Color(0xFF1769AA));

    return AppSemanticColors(
      success: success.primary,
      onSuccess: success.onPrimary,
      successContainer: success.primaryContainer,
      onSuccessContainer: success.onPrimaryContainer,
      warning: warning.primary,
      onWarning: warning.onPrimary,
      warningContainer: warning.primaryContainer,
      onWarningContainer: warning.onPrimaryContainer,
      info: info.primary,
      onInfo: info.onPrimary,
      infoContainer: info.primaryContainer,
      onInfoContainer: info.onPrimaryContainer,
      privacy: scheme.tertiary,
      onPrivacy: scheme.onTertiary,
      privacyContainer: scheme.tertiaryContainer,
      onPrivacyContainer: scheme.onTertiaryContainer,
    );
  }

  static AppSemanticColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppSemanticColors>() ??
        AppSemanticColors.from(theme.colorScheme);
  }

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? privacy,
    Color? onPrivacy,
    Color? privacyContainer,
    Color? onPrivacyContainer,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      privacy: privacy ?? this.privacy,
      onPrivacy: onPrivacy ?? this.onPrivacy,
      privacyContainer: privacyContainer ?? this.privacyContainer,
      onPrivacyContainer: onPrivacyContainer ?? this.onPrivacyContainer,
    );
  }

  @override
  AppSemanticColors lerp(covariant AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      privacy: Color.lerp(privacy, other.privacy, t)!,
      onPrivacy: Color.lerp(onPrivacy, other.onPrivacy, t)!,
      privacyContainer: Color.lerp(
        privacyContainer,
        other.privacyContainer,
        t,
      )!,
      onPrivacyContainer: Color.lerp(
        onPrivacyContainer,
        other.onPrivacyContainer,
        t,
      )!,
    );
  }
}

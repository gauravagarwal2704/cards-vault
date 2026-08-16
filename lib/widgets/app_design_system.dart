import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// A theme-aware contained surface with complete Material interaction states.
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.color,
    this.foregroundColor,
    this.shape = AppShapes.large,
    this.border,
    this.semanticLabel,
    this.selected,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? foregroundColor;
  final ShapeBorder shape;
  final BorderSide? border;
  final String? semanticLabel;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveShape = border == null
        ? shape
        : switch (shape) {
            RoundedRectangleBorder rounded => rounded.copyWith(side: border),
            StadiumBorder stadium => stadium.copyWith(side: border),
            _ => shape,
          };

    Widget content = child;
    if (foregroundColor != null) {
      content = IconTheme.merge(
        data: IconThemeData(color: foregroundColor),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foregroundColor),
          child: content,
        ),
      );
    }

    Widget surface = Material(
      color: color ?? scheme.surfaceContainerLow,
      shape: effectiveShape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: content)
          : InkWell(
              onTap: onTap,
              customBorder: effectiveShape,
              child: Padding(padding: padding, child: content),
            ),
    );

    if (semanticLabel != null || selected != null) {
      surface = Semantics(
        button: onTap != null,
        label: semanticLabel,
        selected: selected,
        child: surface,
      );
    }
    return surface;
  }
}

class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.trailing,
  });

  final String title;
  final String? description;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTypography.sectionTitle(color: scheme.onSurface),
              ),
            ),
            ?trailing,
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            description!,
            style: AppTypography.body(color: scheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}

enum AppStatusKind { success, warning, info, error, privacy }

class AppStatusMessage extends StatelessWidget {
  const AppStatusMessage({
    super.key,
    required this.kind,
    required this.message,
    this.title,
    this.action,
    this.icon,
  });

  final AppStatusKind kind;
  final String? title;
  final String message;
  final Widget? action;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);
    final (container, foreground, defaultIcon) = switch (kind) {
      AppStatusKind.success => (
        semantic.successContainer,
        semantic.onSuccessContainer,
        Icons.check_circle_outline,
      ),
      AppStatusKind.warning => (
        semantic.warningContainer,
        semantic.onWarningContainer,
        Icons.warning_amber_rounded,
      ),
      AppStatusKind.info => (
        semantic.infoContainer,
        semantic.onInfoContainer,
        Icons.info_outline_rounded,
      ),
      AppStatusKind.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline_rounded,
      ),
      AppStatusKind.privacy => (
        semantic.privacyContainer,
        semantic.onPrivacyContainer,
        Icons.shield_outlined,
      ),
    };

    return Semantics(
      liveRegion: true,
      child: AppSurface(
        color: container,
        shape: AppShapes.medium,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon ?? defaultIcon, color: foreground),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(title!, style: AppTypography.label(color: foreground)),
                    const SizedBox(height: AppSpacing.xxs),
                  ],
                  Text(message, style: AppTypography.body(color: foreground)),
                ],
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: AppSpacing.xs),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

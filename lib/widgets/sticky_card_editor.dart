import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// Keeps the live card above the form while its fields scroll underneath.
class StickyCardEditor extends StatelessWidget {
  final Widget preview;
  final Widget fields;
  final Widget? banner;
  final Color backgroundColor;

  const StickyCardEditor({
    super.key,
    required this.preview,
    required this.fields,
    required this.backgroundColor,
    this.banner,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Leave usable space for fields on short screens and above the keyboard.
        final cardWidth = math.min(
          math.min(680.0, constraints.maxWidth - AppSpacing.lg * 2),
          constraints.maxHeight * 0.45 * 1.586,
        );
        return CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            if (banner != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    0,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: banner,
                    ),
                  ),
                ),
              ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _CardPreviewHeader(
                height: cardWidth / 1.586 + AppSpacing.lg + AppSpacing.xs,
                cardWidth: cardWidth,
                backgroundColor: backgroundColor,
                preview: preview,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: fields,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CardPreviewHeader extends SliverPersistentHeaderDelegate {
  final double height;
  final double cardWidth;
  final Color backgroundColor;
  final Widget preview;

  _CardPreviewHeader({
    required this.height,
    required this.cardWidth,
    required this.backgroundColor,
    required this.preview,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: backgroundColor,
      child: Padding(
        // Keep a compact gap below the card, including its six-pixel lift.
        padding: const EdgeInsets.only(
          top: AppSpacing.lg,
          bottom: AppSpacing.xs,
        ),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: shrinkOffset > 0 || overlapsContent ? 1 : 0),
            duration: AppMotion.resolve(context, AppMotion.standard),
            curve: AppMotion.standardCurve,
            child: SizedBox(width: cardWidth, child: preview),
            builder: (context, lift, child) {
              return Transform.translate(
                offset: Offset(0, -6 * lift),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12 * lift),
                        blurRadius: 18 * lift,
                        offset: Offset(0, 8 * lift),
                      ),
                    ],
                  ),
                  child: child,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CardPreviewHeader oldDelegate) =>
      height != oldDelegate.height ||
      cardWidth != oldDelegate.cardWidth ||
      backgroundColor != oldDelegate.backgroundColor ||
      preview != oldDelegate.preview;
}

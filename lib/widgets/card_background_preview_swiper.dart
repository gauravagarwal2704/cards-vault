import 'package:flutter/material.dart';

/// Adds horizontal background browsing to the full-size add/edit card preview.
///
/// A swipe to the left advances to the next background, while a swipe to the
/// right selects the previous one. The parent owns the selected background so
/// this gesture stays synchronized with the background picker.
class CardBackgroundPreviewSwiper extends StatefulWidget {
  final bool enabled;
  final Object backgroundKey;
  final ValueChanged<int> onCycle;
  final Widget child;

  const CardBackgroundPreviewSwiper({
    super.key,
    required this.enabled,
    required this.backgroundKey,
    required this.onCycle,
    required this.child,
  });

  @override
  State<CardBackgroundPreviewSwiper> createState() =>
      _CardBackgroundPreviewSwiperState();
}

class _CardBackgroundPreviewSwiperState
    extends State<CardBackgroundPreviewSwiper> {
  static const _minimumDragDistance = 36.0;
  static const _minimumFlingVelocity = 250.0;

  double _horizontalDragDistance = 0;

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    _horizontalDragDistance += details.delta.dx;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final hasDrag = _horizontalDragDistance.abs() >= _minimumDragDistance;
    final hasFling = velocity.abs() >= _minimumFlingVelocity;

    if (hasDrag || hasFling) {
      final movement = hasDrag ? _horizontalDragDistance : velocity;
      widget.onCycle(movement < 0 ? 1 : -1);
    }

    _horizontalDragDistance = 0;
  }

  void _onHorizontalDragCancel() {
    _horizontalDragDistance = 0;
  }

  @override
  Widget build(BuildContext context) {
    final preview = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: KeyedSubtree(
        key: ValueKey(widget.backgroundKey),
        child: widget.child,
      ),
    );

    return Semantics(
      label: 'Card background preview',
      hint: widget.enabled
          ? 'Swipe left or right to browse card backgrounds'
          : null,
      onIncrease: widget.enabled ? () => widget.onCycle(1) : null,
      onDecrease: widget.enabled ? () => widget.onCycle(-1) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: widget.enabled ? _onHorizontalDragUpdate : null,
        onHorizontalDragEnd: widget.enabled ? _onHorizontalDragEnd : null,
        onHorizontalDragCancel: widget.enabled ? _onHorizontalDragCancel : null,
        child: preview,
      ),
    );
  }
}

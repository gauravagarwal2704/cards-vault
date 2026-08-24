import 'dart:math';
import 'dart:ui';

/// Converts coordinates from a [BoxFit.cover] camera preview into normalized
/// camera sensor coordinates.
class CameraPreviewGeometry {
  CameraPreviewGeometry._();

  static Offset normalizedPointForCover({
    required Offset viewportPoint,
    required Size viewportSize,
    required Size orientedPreviewSize,
  }) {
    final layout = _coverLayout(viewportSize, orientedPreviewSize);
    return Offset(
      ((viewportPoint.dx - layout.offset.dx) / layout.size.width).clamp(0, 1),
      ((viewportPoint.dy - layout.offset.dy) / layout.size.height).clamp(0, 1),
    );
  }

  static Rect normalizedRectForCover({
    required Rect viewportRect,
    required Size viewportSize,
    required Size orientedPreviewSize,
  }) {
    final layout = _coverLayout(viewportSize, orientedPreviewSize);
    return Rect.fromLTWH(
      ((viewportRect.left - layout.offset.dx) / layout.size.width).clamp(0, 1),
      ((viewportRect.top - layout.offset.dy) / layout.size.height).clamp(0, 1),
      (viewportRect.width / layout.size.width).clamp(0, 1),
      (viewportRect.height / layout.size.height).clamp(0, 1),
    );
  }

  static ({Size size, Offset offset}) _coverLayout(
    Size viewportSize,
    Size previewSize,
  ) {
    if (viewportSize.isEmpty || previewSize.isEmpty) {
      return (size: const Size(1, 1), offset: Offset.zero);
    }
    final scale = max(
      viewportSize.width / previewSize.width,
      viewportSize.height / previewSize.height,
    );
    final displayedSize = Size(
      previewSize.width * scale,
      previewSize.height * scale,
    );
    return (
      size: displayedSize,
      offset: Offset(
        (viewportSize.width - displayedSize.width) / 2,
        (viewportSize.height - displayedSize.height) / 2,
      ),
    );
  }
}

import 'package:cards_wallet/utils/camera_preview_geometry.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps the visible preview center to the camera center', () {
    final point = CameraPreviewGeometry.normalizedPointForCover(
      viewportPoint: const Offset(180, 400),
      viewportSize: const Size(360, 800),
      orientedPreviewSize: const Size(720, 1280),
    );

    expect(point.dx, closeTo(0.5, 0.0001));
    expect(point.dy, closeTo(0.5, 0.0001));
  });

  test('accounts for horizontally cropped BoxFit.cover preview pixels', () {
    const viewport = Size(360, 800);
    const preview = Size(720, 1280);

    final left = CameraPreviewGeometry.normalizedPointForCover(
      viewportPoint: const Offset(0, 400),
      viewportSize: viewport,
      orientedPreviewSize: preview,
    );
    final right = CameraPreviewGeometry.normalizedPointForCover(
      viewportPoint: const Offset(360, 400),
      viewportSize: viewport,
      orientedPreviewSize: preview,
    );

    // The 720:1280 preview is 450 px wide after covering this viewport, so
    // 45 px are cropped from each side and visible taps map to 0.1...0.9.
    expect(left.dx, closeTo(0.1, 0.0001));
    expect(right.dx, closeTo(0.9, 0.0001));
  });

  test('uses the same cover mapping for the OCR card rectangle', () {
    final rect = CameraPreviewGeometry.normalizedRectForCover(
      viewportRect: const Rect.fromLTWH(90, 240, 180, 320),
      viewportSize: const Size(360, 800),
      orientedPreviewSize: const Size(720, 1280),
    );

    expect(rect.left, closeTo(0.3, 0.0001));
    expect(rect.top, closeTo(0.3, 0.0001));
    expect(rect.width, closeTo(0.4, 0.0001));
    expect(rect.height, closeTo(0.4, 0.0001));
  });
}

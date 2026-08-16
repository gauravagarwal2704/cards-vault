import 'dart:io';

class NormalizedCardCrop {
  final double left;
  final double top;
  final double width;
  final double height;

  const NormalizedCardCrop({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

/// Images captured for one scan attempt.
///
/// Camera captures are owned by the scan flow and deleted immediately after
/// recognition. Gallery images are never owned, so the user's source photo is
/// left untouched.
class CardScanCapture {
  final List<String> imagePaths;
  final bool ownsFiles;
  final NormalizedCardCrop? crop;

  const CardScanCapture({
    required this.imagePaths,
    required this.ownsFiles,
    this.crop,
  });

  String? get primaryImagePath => imagePaths.isEmpty ? null : imagePaths.first;

  Future<void> deleteOwnedFiles() async {
    if (!ownsFiles) return;
    for (final imagePath in imagePaths) {
      try {
        final file = File(imagePath);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best-effort cleanup; recognition must not fail because the camera
        // plugin has already reclaimed one of its temporary files.
      }
    }
  }
}

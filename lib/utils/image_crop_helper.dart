import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';

/// Credit card aspect ratio (85.6mm x 53.98mm). Used as the starting frame when
/// cropping a card for OCR so the card fills the frame without letterboxing.
const _cardAspectRatio = CropAspectRatio(ratioX: 1.586, ratioY: 1);

/// Opens the platform crop editor for [sourcePath]. Returns the cropped file, or
/// null if the user cancelled.
Future<File?> cropImageFile(
  BuildContext context,
  String sourcePath, {
  String toolbarTitle = 'Crop photo',
  bool startWithCardRatio = false,
}) async {
  final themeProvider = context.read<ThemeProvider>();

  final cropped = await ImageCropper().cropImage(
    sourcePath: sourcePath,
    maxWidth: 1920,
    compressQuality: 88,
    aspectRatio: startWithCardRatio ? _cardAspectRatio : null,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: toolbarTitle,
        toolbarColor: themeProvider.getBackgroundColor(),
        toolbarWidgetColor: themeProvider.getPrimaryTextColor(),
        backgroundColor: themeProvider.getBackgroundColor(),
        activeControlsWidgetColor: themeProvider.getPrimaryColor(),
        lockAspectRatio: false,
        initAspectRatio: CropAspectRatioPreset.original,
        aspectRatioPresets: const [
          CropAspectRatioPreset.original,
          CropAspectRatioPreset.square,
          CropAspectRatioPreset.ratio3x2,
          CropAspectRatioPreset.ratio4x3,
          CropAspectRatioPreset.ratio16x9,
        ],
      ),
      IOSUiSettings(
        title: toolbarTitle,
        aspectRatioLockEnabled: false,
        resetAspectRatioEnabled: true,
        aspectRatioPresets: const [
          CropAspectRatioPreset.original,
          CropAspectRatioPreset.square,
          CropAspectRatioPreset.ratio3x2,
          CropAspectRatioPreset.ratio4x3,
          CropAspectRatioPreset.ratio16x9,
        ],
      ),
    ],
  );

  return cropped == null ? null : File(cropped.path);
}

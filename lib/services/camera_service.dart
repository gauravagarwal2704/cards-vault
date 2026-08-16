import 'package:flutter/material.dart';

import '../screens/card_camera_screen.dart';
import 'ocr_service.dart';

class CameraService {
  Future<OCRResult?> scanCard(BuildContext context) async {
    try {
      return await Navigator.push<OCRResult>(
        context,
        MaterialPageRoute(builder: (context) => const CardCameraScreen()),
      );
    } catch (e) {
      throw Exception('Failed to scan card: $e');
    }
  }
}

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../screens/card_camera_screen.dart';

class CameraService {
  final ImagePicker _picker = ImagePicker();

  Future<String?> captureCardImage(BuildContext context) async {
    try {
      final String? imagePath = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => const CardCameraScreen(),
        ),
      );

      return imagePath;
    } catch (e) {
      throw Exception('Failed to capture card image: $e');
    }
  }

  Future<String?> captureImage() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 95,
      );

      if (photo != null) {
        return photo.path;
      }
      return null;
    } catch (e) {
      throw Exception('Failed to capture image: $e');
    }
  }

  Future<String?> pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );

      if (image != null) {
        return image.path;
      }
      return null;
    } catch (e) {
      throw Exception('Failed to pick image: $e');
    }
  }
}


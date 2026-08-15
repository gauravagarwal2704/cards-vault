import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/camera_service.dart';
import '../services/ocr_service.dart';
import '../utils/image_utils.dart';

enum CameraState {
  idle,
  capturing,
  validating,
  processing,
  success,
  error,
}

class CameraProvider extends ChangeNotifier {
  final CameraService _cameraService = CameraService();
  final OCRService _ocrService = OCRService();

  CameraState _state = CameraState.idle;
  OCRResult? _ocrResult;
  String? _errorMessage;
  String? _imagePath;
  ImageQuality? _imageQuality;

  CameraState get state => _state;
  OCRResult? get ocrResult => _ocrResult;
  String? get errorMessage => _errorMessage;
  String? get imagePath => _imagePath;
  ImageQuality? get imageQuality => _imageQuality;

  Future<void> captureAndProcessCard(BuildContext context) async {
    _state = CameraState.capturing;
    _errorMessage = null;
    _ocrResult = null;
    _imagePath = null;
    _imageQuality = null;
    notifyListeners();

    try {
      String? imagePath = await _cameraService.captureCardImage(context);

      if (imagePath == null) {
        _state = CameraState.idle;
        notifyListeners();
        return;
      }

      _imagePath = imagePath;
      _state = CameraState.validating;
      notifyListeners();

      ImageQuality quality = await ImageUtils.validateImageQuality(imagePath);
      _imageQuality = quality;

      if (!quality.isGoodQuality) {
        _state = CameraState.error;
        _errorMessage = quality.warning ?? 'Image quality is poor. Please try again.';
        notifyListeners();
        return;
      }

      _state = CameraState.processing;
      notifyListeners();

      OCRResult result = await _ocrService.processImage(imagePath, preprocess: true);

      if (result.cardNumber == null) {
        _state = CameraState.error;
        _errorMessage = 'Could not detect card number. Please ensure the card is clearly visible and well-lit, then try again.';
      } else {
        _ocrResult = result;
        _state = CameraState.success;
        _errorMessage = null;
      }
      notifyListeners();
    } catch (e) {
      _state = CameraState.error;
      
      String errorString = e.toString().toLowerCase();
      
      if (errorString.contains('permission')) {
        _errorMessage = 'Camera permission denied. Please enable camera access in settings.';
      } else if (errorString.contains('camera')) {
        _errorMessage = 'Failed to access camera. Please try again.';
      } else if (errorString.contains('process')) {
        _errorMessage = 'Failed to process image. Please ensure the card is clearly visible.';
      } else {
        _errorMessage = 'An error occurred. Please try again.';
      }
      
      notifyListeners();
    }
  }

  Future<void> pickFromGalleryAndProcess() async {
    _state = CameraState.capturing;
    _errorMessage = null;
    _ocrResult = null;
    _imagePath = null;
    _imageQuality = null;
    notifyListeners();

    try {
      String? imagePath = await _cameraService.pickImageFromGallery();

      if (imagePath == null) {
        _state = CameraState.idle;
        notifyListeners();
        return;
      }

      _imagePath = imagePath;
      _state = CameraState.validating;
      notifyListeners();

      ImageQuality quality = await ImageUtils.validateImageQuality(imagePath);
      _imageQuality = quality;

      if (!quality.isGoodQuality) {
        _state = CameraState.error;
        _errorMessage = quality.warning ?? 'Image quality is poor. Please try again with a better image.';
        notifyListeners();
        return;
      }

      _state = CameraState.processing;
      notifyListeners();

      OCRResult result = await _ocrService.processImage(imagePath, preprocess: true);

      if (result.cardNumber == null) {
        _state = CameraState.error;
        _errorMessage = 'Could not detect card number. Please ensure the card is clearly visible and well-lit, then try again.';
      } else {
        _ocrResult = result;
        _state = CameraState.success;
        _errorMessage = null;
      }
      notifyListeners();
    } catch (e) {
      _state = CameraState.error;
      
      String errorString = e.toString().toLowerCase();
      
      if (errorString.contains('permission')) {
        _errorMessage = 'Gallery permission denied. Please enable access in settings.';
      } else if (errorString.contains('process')) {
        _errorMessage = 'Failed to process image. Please ensure the card is clearly visible.';
      } else {
        _errorMessage = 'An error occurred. Please try again.';
      }
      
      notifyListeners();
    }
  }

  void reset() {
    _state = CameraState.idle;
    _ocrResult = null;
    _errorMessage = null;
    _imagePath = null;
    _imageQuality = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    if (_state == CameraState.error) {
      _state = CameraState.idle;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }
}


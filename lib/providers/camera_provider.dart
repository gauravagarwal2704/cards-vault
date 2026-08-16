import 'package:flutter/material.dart';

import '../services/camera_service.dart';
import '../services/ocr_service.dart';

enum CameraState { idle, capturing, validating, processing, success, error }

class CameraProvider extends ChangeNotifier {
  final CameraService _cameraService = CameraService();

  CameraState _state = CameraState.idle;
  OCRResult? _ocrResult;
  String? _errorMessage;

  CameraState get state => _state;
  OCRResult? get ocrResult => _ocrResult;
  String? get errorMessage => _errorMessage;

  Future<void> captureAndProcessCard(BuildContext context) async {
    _beginCapture();
    try {
      final result = await _cameraService.scanCard(context);
      if (result == null) {
        _state = CameraState.idle;
        notifyListeners();
        return;
      }
      _ocrResult = result;
      _state = CameraState.success;
      _errorMessage = null;
      notifyListeners();
    } catch (error) {
      _handleError(error, gallery: false);
    }
  }

  void _beginCapture() {
    _state = CameraState.capturing;
    _errorMessage = null;
    _ocrResult = null;
    notifyListeners();
  }

  void _handleError(Object error, {required bool gallery}) {
    _state = CameraState.error;
    final message = error.toString().toLowerCase();
    if (message.contains('permission')) {
      _errorMessage = gallery
          ? 'Photo permission was denied. Enable it in system settings.'
          : 'Camera permission was denied. Enable it in system settings.';
    } else {
      _errorMessage = gallery
          ? 'The photo could not be processed. Try a clearer image.'
          : 'The scan could not be processed. Please try again.';
    }
    notifyListeners();
  }

  void reset() {
    _state = CameraState.idle;
    _ocrResult = null;
    _errorMessage = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    if (_state == CameraState.error) _state = CameraState.idle;
    notifyListeners();
  }
}

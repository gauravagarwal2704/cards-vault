import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/card_scan_capture.dart';
import '../services/ai_card_scan_service.dart';
import '../services/ai_scan_settings_service.dart';
import '../services/ocr_service.dart';
import '../services/local_card_scan_service.dart';
import '../services/app_log_service.dart';
import '../utils/camera_preview_geometry.dart';
import '../utils/card_network_utils.dart';
import '../utils/image_utils.dart';
import '../theme/app_motion.dart';
import '../theme/app_colors.dart';
import 'ai_scan_settings_screen.dart';

class CardCameraScreen extends StatefulWidget {
  const CardCameraScreen({super.key});

  @override
  State<CardCameraScreen> createState() => _CardCameraScreenState();
}

class _CardCameraScreenState extends State<CardCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _isFlashOn = false;
  bool _isCapturing = false;
  bool _isPickingGallery = false;
  bool _isProcessing = false;
  bool _isPortraitCard = false;
  int _initializationGeneration = 0;
  int _processingStep = 1;
  bool _processingUsesAi = false;
  bool _processingComplete = false;
  bool _galleryStripeFallback = false;
  String _processingMessage = 'Reading card securely on this device…';
  List<String> _processingImagePaths = const [];
  String? _bestProcessingImagePath;
  String? _errorMessage;
  String? _errorDetails;
  bool _isAiError = false;
  Offset? _focusIndicatorPosition;
  bool _focusIndicatorSettled = false;
  int _focusRequestGeneration = 0;
  final OCRService _ocrService = OCRService();
  final LocalCardScanService _localCardScanService =
      const LocalCardScanService();
  final AiScanSettingsService _aiSettingsService = AiScanSettingsService();
  final AiCardScanService _aiScanService = AiCardScanService();
  _LiveScanQuality _liveQuality = const _LiveScanQuality(
    message: 'Align the card, tap to focus, then scan',
    isReady: true,
    tone: _ScanQualityTone.neutral,
  );

  @override
  void initState() {
    super.initState();
    AppLogService.instance.action(
      'Navigation',
      'Opened card scanner',
      details: {'platformScanner': _usesNativeScannerOnly},
    );
    WidgetsBinding.instance.addObserver(this);
    if (_usesNativeScannerOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_scanWithLocalCardScan(closeOnCancel: true));
      });
    } else {
      unawaited(_initializeCamera());
    }
  }

  bool get _usesNativeScannerOnly => Platform.isAndroid;

  bool _isClosing = false;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_releaseCamera().whenComplete(_ocrService.dispose));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On Android the native CardScan activity owns the only camera session.
    // Its pause/resume transitions must never start Flutter's camera plugin.
    if (_usesNativeScannerOnly) return;

    // Permission sheets and the gallery can briefly mark the app inactive.
    // Disposing then races the initial camera permission request and caused the
    // first scanner opening to remain on its loading screen.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _focusIndicatorPosition = null;
      _isInitializing = false;
      unawaited(_releaseCamera());
    } else if (state == AppLifecycleState.resumed) {
      final controller = _controller;
      if (!_isClosing &&
          !_isPickingGallery &&
          !_isCapturing &&
          !_isProcessing &&
          (controller == null || !controller.value.isInitialized)) {
        _initializeCamera();
      }
    }
  }

  Future<void> _popScanner([Object? result]) async {
    if (_isClosing) return;
    _isClosing = true;
    try {
      await _releaseCamera();
    } finally {
      if (mounted) Navigator.of(context).pop(result);
    }
  }

  Future<void> _releaseCamera() async {
    _initializationGeneration++;
    _focusRequestGeneration++;
    final controller = _controller;
    _controller = null;
    _isInitialized = false;
    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  Future<void> _stopAndDispose(CameraController? controller) async {
    if (controller == null) return;
    try {
      await controller.dispose();
    } catch (_) {}
  }

  Widget _withCloseGuard(Widget child) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_popScanner(result));
      },
      child: child,
    );
  }

  Future<void> _initializeCamera() async {
    if (_isInitializing ||
        _isPickingGallery ||
        _isCapturing ||
        _isProcessing ||
        _isClosing) {
      return;
    }
    final generation = ++_initializationGeneration;
    if (mounted) {
      setState(() {
        _isInitializing = true;
        _errorMessage = null;
        _errorDetails = null;
        _isAiError = false;
      });
    }
    try {
      final cameras = await availableCameras().timeout(
        const Duration(seconds: 8),
      );
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _isInitializing = false;
            _errorMessage = 'No camera is available.';
          });
        }
        return;
      }

      final camera = cameras.firstWhere(
        (candidate) => candidate.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final previous = _controller;
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _controller = controller;
      await _stopAndDispose(previous);
      await controller.initialize().timeout(const Duration(seconds: 12));
      if (!mounted || _isClosing || generation != _initializationGeneration) {
        await _stopAndDispose(controller);
        return;
      }
      await controller.setFlashMode(FlashMode.off);
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setExposureMode(ExposureMode.auto);
        await _applyCameraFocus(controller, const Offset(0.5, 0.5));
      } catch (_) {
        // Some desktop and older mobile camera implementations do not expose
        // focus/exposure controls.
      }
      if (!mounted || _isClosing || generation != _initializationGeneration) {
        await _stopAndDispose(controller);
        return;
      }
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isInitializing = false;
          _errorMessage = null;
        });
      }
    } catch (error) {
      if (mounted && !_isClosing && generation == _initializationGeneration) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'CardVault could not start the camera. Check camera permission and try again.';
          _errorDetails = null;
        });
      }
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final enable = !_isFlashOn;
      await controller.setFlashMode(enable ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _isFlashOn = enable);
    } catch (_) {
      if (mounted) {
        setState(() {
          _liveQuality = const _LiveScanQuality(
            message: 'Flash is not available on this camera',
            isReady: false,
            tone: _ScanQualityTone.warning,
          );
        });
      }
    }
  }

  Future<bool> _applyCameraFocus(
    CameraController controller,
    Offset normalizedPoint,
  ) async {
    try {
      await controller.setFocusMode(FocusMode.auto);
    } catch (_) {
      // Setting a point can still trigger autofocus on cameras that do not
      // expose focus-mode control separately.
    }

    var focusPointApplied = false;
    try {
      await controller.setFocusPoint(normalizedPoint);
      focusPointApplied = true;
    } catch (_) {
      // Fixed-focus and older cameras may not expose a focus point.
    }
    try {
      await controller.setExposurePoint(normalizedPoint);
    } catch (_) {
      // Exposure metering is useful but not required for tap-to-focus.
    }
    return focusPointApplied;
  }

  Future<void> _focusAt(Offset viewportPoint, Size viewportSize) async {
    final controller = _controller;
    if (_isCapturing ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.previewSize == null) {
      return;
    }

    final preview = controller.value.previewSize!;
    final normalizedPoint = CameraPreviewGeometry.normalizedPointForCover(
      viewportPoint: viewportPoint,
      viewportSize: viewportSize,
      orientedPreviewSize: Size(preview.height, preview.width),
    );
    final request = ++_focusRequestGeneration;
    HapticFeedback.selectionClick();
    setState(() {
      _focusIndicatorPosition = viewportPoint;
      _focusIndicatorSettled = false;
    });

    final applied = await _applyCameraFocus(controller, normalizedPoint);
    if (!mounted || request != _focusRequestGeneration) return;
    if (!applied) {
      setState(() {
        _focusIndicatorPosition = null;
        _liveQuality = const _LiveScanQuality(
          message:
              'This camera uses fixed focus — keep the card near the center',
          isReady: false,
          tone: _ScanQualityTone.warning,
        );
      });
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (!mounted || request != _focusRequestGeneration) return;
    setState(() => _focusIndicatorSettled = true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted || request != _focusRequestGeneration) return;
    setState(() => _focusIndicatorPosition = null);
  }

  Future<void> _scanWithLocalCardScan({bool closeOnCancel = false}) async {
    final controller = _controller;
    if (_isCapturing ||
        (!_usesNativeScannerOnly &&
            (controller == null || !controller.value.isInitialized))) {
      return;
    }
    final span = AppLogService.instance.startSpan(
      'Scanning',
      'Native local card scan',
    );
    HapticFeedback.mediumImpact();
    AppLogService.instance.action('Scanning', 'Local card scan started');
    setState(() {
      _isCapturing = true;
      _galleryStripeFallback = false;
      _focusIndicatorPosition = null;
      _errorMessage = null;
      _errorDetails = null;
      _liveQuality = const _LiveScanQuality(
        message: 'Opening the live card scanner…',
        isReady: true,
        tone: _ScanQualityTone.neutral,
      );
    });

    // CameraX must own the camera while Stripe's portable scanner analyzes
    // preview frames. Releasing Flutter's controller avoids two camera clients
    // racing each other, a common source of scanner crashes.
    await _releaseCamera();
    String? acceptedImagePath;
    try {
      final scan = await _localCardScanService.scan();
      acceptedImagePath = scan.imagePath;
      if (!mounted || _isClosing) return;

      if (!scan.completed) {
        span.complete(
          details: {
            'success': false,
            'reason': scan.cancellationReason ?? 'cancelled',
          },
        );
        AppLogService.instance.action(
          'Scanning',
          'Local card scan ended without a result',
          details: {'reason': scan.cancellationReason ?? 'cancelled'},
        );
        setState(() {
          _isCapturing = false;
          _liveQuality = _scanCanceledGuidance(scan.cancellationReason);
        });
        if (closeOnCancel) {
          await _popScanner();
          return;
        }
        await _initializeCamera();
        return;
      }

      OCRResult localText = const OCRResult();
      if (acceptedImagePath != null) {
        if (mounted) {
          setState(() {
            _liveQuality = const _LiveScanQuality(
              message: 'Reading expiry date and cardholder name…',
              isReady: true,
              tone: _ScanQualityTone.neutral,
            );
          });
        }
        localText = await _ocrService
            .processImage(
              acceptedImagePath,
              // Native gallery import now returns a bounded, centered card
              // crop instead of the original full-resolution photo.
              imageIsCardCrop: true,
              preprocess: scan.pan != null,
              timeBudget: const Duration(milliseconds: 2800),
            )
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () => const OCRResult(),
            );
      }
      final result = scan.pan == null
          ? localText
          : _withVerifiedPan(localText, scan.pan!);
      if (result.cardNumber == null) {
        span.complete(details: {'success': false, 'reason': 'noCardNumber'});
        AppLogService.instance.action(
          'Scanning',
          'Local card scan could not identify a card',
        );
        if (mounted && !_isClosing) {
          setState(() {
            _isCapturing = false;
            _errorDetails = null;
            _errorMessage = 'CardVault could not identify the card number. Try another photo or enter it manually.';
          });
        }
        return;
      }
      if (!mounted || _isClosing) return;
      setState(() {
        _isCapturing = false;
        _liveQuality = const _LiveScanQuality(
          message: 'Card number verified',
          isReady: true,
          tone: _ScanQualityTone.ready,
        );
      });
      HapticFeedback.lightImpact();
      AppLogService.instance.action('Scanning', 'Local card scan succeeded');
      span.complete(details: {'success': true});
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (mounted) await _popScanner(result);
    } on PlatformException catch (error, stackTrace) {
      span.fail(error, stackTrace);
      AppLogService.instance.record(
        'Scanning',
        'Local card scanner platform error: ${error.code}',
      );
      if (mounted && !_isClosing) {
        setState(() {
          _isCapturing = false;
          _errorMessage = 'The local Android card scanner could not start.';
          _errorDetails = null;
        });
        if (!_usesNativeScannerOnly) await _initializeCamera();
      }
    } catch (error, stackTrace) {
      span.fail(error, stackTrace);
      rethrow;
    } finally {
      if (acceptedImagePath != null) {
        await CardScanCapture(
          imagePaths: [acceptedImagePath],
          ownsFiles: true,
        ).deleteOwnedFiles();
      }
    }
  }

  OCRResult _withVerifiedPan(OCRResult localText, String verifiedPan) {
    final warnings = <String>{
      ...localText.reviewWarnings.where((warning) {
        final normalized = warning.toLowerCase();
        // These field-specific warnings are rebuilt below after merging the
        // PAN verified by the live model with the accepted-frame text OCR.
        return !normalized.contains('card number') &&
            !normalized.contains('pan') &&
            !normalized.contains('expiry') &&
            !normalized.contains('cardholder name');
      }),
      if (localText.expiryDate == null) 'Expiry date was not read',
      if (localText.cardholderName == null) 'Cardholder name was not read',
    };
    final textConfidence = [
      localText.expiryDateConfidence,
      localText.cardholderNameConfidence,
    ].where((confidence) => confidence > 0).toList();
    final averageTextConfidence = textConfidence.isEmpty
        ? 0.72
        : textConfidence.reduce((a, b) => a + b) / textConfidence.length;
    return OCRResult(
      cardNumber: verifiedPan,
      expiryDate: localText.expiryDate,
      cardholderName: localText.cardholderName,
      cardType: CardNetworkUtils.cardTypeFromNumber(verifiedPan),
      cardNumberConfidence: 0.99,
      expiryDateConfidence: localText.expiryDateConfidence,
      cardholderNameConfidence: localText.cardholderNameConfidence,
      overallConfidence: (0.99 + averageTextConfidence) / 2,
      supportingFrames: 3,
      reviewWarnings: warnings.toList(growable: false),
    );
  }

  _LiveScanQuality _scanCanceledGuidance(String? reason) {
    return _LiveScanQuality(
      message: reason == 'timeout'
          ? 'Card not found in 20 seconds — reposition it and try again'
          : 'Scan canceled — ready to try again',
      isReady: false,
      tone: _ScanQualityTone.warning,
    );
  }

  Future<void> _pickFromGallery() async {
    if (_isCapturing || _isPickingGallery || _isProcessing) return;
    setState(() {
      _isPickingGallery = true;
      _processingMessage = 'Opening your photo library…';
      _errorMessage = null;
      _errorDetails = null;
      _isAiError = false;
    });
    AppLogService.instance.action('Scanning', 'Gallery picker opened');
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (!mounted) return;
      if (image == null) {
        AppLogService.instance.action('Scanning', 'Gallery picker cancelled');
        setState(() => _isPickingGallery = false);
        final current = _controller;
        if (current == null || !current.value.isInitialized) {
          await _initializeCamera();
        }
        return;
      }
      await _processCapture(
        CardScanCapture(imagePaths: [image.path], ownsFiles: false),
        fromGallery: true,
      );
    } catch (error) {
      AppLogService.instance.record(
        'Scanning',
        'Gallery image selection failed: $error',
      );
      if (mounted) {
        setState(() {
          _isPickingGallery = false;
          _errorMessage = 'The selected photo could not be opened.';
          _errorDetails = null;
        });
      }
    }
  }

  Future<void> _processCapture(
    CardScanCapture capture, {
    required bool fromGallery,
  }) async {
    if (!mounted) return;
    final span = AppLogService.instance.startSpan(
      'Scanning',
      'Process captured card image',
      details: {
        'source': fromGallery ? 'gallery' : 'camera',
        'frameCount': capture.imagePaths.length,
      },
    );
    setState(() {
      _isCapturing = false;
      _isPickingGallery = fromGallery;
      _isProcessing = true;
      _processingStep = _galleryStripeFallback ? 2 : 1;
      _processingUsesAi = false;
      _processingComplete = false;
      _processingImagePaths = List.unmodifiable(capture.imagePaths);
      _bestProcessingImagePath = null;
      _processingMessage = fromGallery
          ? _galleryStripeFallback
                ? 'Stripe could not verify this photo — trying the offline OCR fallback…'
                : 'Checking the selected photo…'
          : 'Checking ${capture.imagePaths.length} captured frames…';
    });

    try {
      final ranked = <({String path, ImageQuality quality})>[];
      for (var index = 0; index < capture.imagePaths.length; index++) {
        if (mounted) {
          setState(() {
            _processingMessage =
                'Checking frame ${index + 1} of ${capture.imagePaths.length}…';
          });
        }
        final path = capture.imagePaths[index];
        final quality = await ImageUtils.validateImageQuality(
          path,
          crop: capture.crop,
        );
        ranked.add((path: path, quality: quality));
      }
      ranked.sort(
        (a, b) => _qualityScore(b.quality).compareTo(_qualityScore(a.quality)),
      );
      if (mounted && ranked.isNotEmpty) {
        setState(() {
          _bestProcessingImagePath = ranked.first.path;
          _processingStep = 2;
          _processingMessage = ranked.length == 1
              ? 'Reading the card offline on this device…'
              : 'Comparing ${ranked.length} frames offline on this device…';
        });
      }

      // Quality is advisory. A strict pre-OCR rejection caused valid gallery
      // photos and slightly reflective cards to fail before text recognition.
      final paths = ranked.map((item) => item.path).take(3).toList();
      var result = await _ocrService.processImages(paths, crop: capture.crop);
      if (mounted) {}

      if (result.cardNumber == null || result.expiryDate == null) {
        final settings = await _aiSettingsService.load();
        if (mounted && settings.isConfigured) {
          final approved = await _confirmAiUpload(settings);
          if (approved && mounted) {
            setState(() {
              _processingStep = 3;
              _processingUsesAi = true;
              _processingMessage =
                  '${settings.provider.modelLabel} is comparing ${paths.length} metadata-free frame${paths.length == 1 ? '' : 's'}…';
            });
            final outcome = await _aiScanService.scan(
              imagePaths: paths,
              crop: capture.crop,
              localResult: result,
              settings: settings,
              onAttempt: (attempt, maxAttempts) {
                if (!mounted) return;
                setState(() {
                  _processingMessage = attempt == 1
                      ? '${settings.provider.modelLabel} is reading the card…'
                      : 'Network retry ${attempt - 1} of ${maxAttempts - 1} with ${settings.provider.label}…';
                });
              },
            );
            result = outcome.result;
            if (mounted) {}
          }
        }
      }

      if (!mounted) return;
      if (result.cardNumber == null) {
        span.complete(
          details: {
            'success': false,
            'usedAi': _processingUsesAi,
            'reason': 'noCardNumber',
          },
        );
        AppLogService.instance.action(
          'Scanning',
          'Image processing completed without a card result',
          details: {'source': fromGallery ? 'gallery' : 'camera'},
        );
        final bestWarning = ranked.isEmpty
            ? null
            : ranked.first.quality.warning;
        setState(() {
          _isProcessing = false;
          _isPickingGallery = false;
          _errorDetails = null;
          _errorMessage = bestWarning == null
              ? 'CardVault could not identify the card number. Try another photo or enter it manually.'
              : '$bestWarning CardVault still could not identify the card number.';
        });
        return;
      }

      setState(() {
        _processingStep = 3;
        _processingComplete = true;
        _processingMessage = 'Card found — opening review…';
      });
      HapticFeedback.lightImpact();
      AppLogService.instance.action(
        'Scanning',
        'Image processing succeeded',
        details: {
          'source': fromGallery ? 'gallery' : 'camera',
          'usedAi': _processingUsesAi,
        },
      );
      span.complete(details: {'success': true, 'usedAi': _processingUsesAi});
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (mounted) await _popScanner(result);
    } on AiCardScanException catch (error, stackTrace) {
      span.fail(error, stackTrace);
      AppLogService.instance.record(
        'Scanning',
        'AI-assisted scan failed: ${error.runtimeType}',
      );
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isPickingGallery = false;
          _isAiError = true;
          _errorMessage = error.userMessage;
          _errorDetails = [
            if (error.diagnostics != null)
              'Provider: ${error.diagnostics!.provider.label}',
            if (error.diagnostics?.httpStatus != null)
              'HTTP status: ${error.diagnostics!.httpStatus}',
            'Attempts: ${error.attempts}',
            'A redacted diagnostic entry was saved in Smart Scan logs.',
          ].join('\n');
        });
      }
    } catch (error, stackTrace) {
      span.fail(error, stackTrace);
      AppLogService.instance.record(
        'Scanning',
        'Image processing failed: ${error.runtimeType}',
      );
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isPickingGallery = false;
          _isAiError = false;
          _errorMessage =
              'The card image could not be processed. Try another photo.';
          _errorDetails = 'Processing error: ${error.runtimeType}';
        });
      }
    } finally {
      await capture.deleteOwnedFiles();
    }
  }

  double _qualityScore(ImageQuality quality) {
    return quality.blurScore +
        quality.contrast * 2 -
        quality.glareRatio * 180 -
        (quality.brightness - 135).abs() * 0.15;
  }

  Future<bool> _confirmAiUpload(AiScanSettings settings) async {
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.auto_awesome_outlined),
        title: const Text('Try AI-assisted scan?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The offline scan could not confidently read every required field. Send up to 3 nearby frames directly to ${settings.provider.label} for processing by ${settings.provider.modelLabel}?',
              ),
              const SizedBox(height: 14),
              const Text(
                'CardVault sends:',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                '• Up to 3 cropped, resized JPEG frames with metadata removed\n'
                '• A request for card number, expiry, cardholder name, and confidence\n'
                '• Instructions to return null when uncertain and never extract CVV\n'
                '• Your saved key as an HTTPS authentication header to the selected provider',
              ),
              const SizedBox(height: 10),
              const Text(
                'It does not send offline OCR text, other saved cards, or unrelated app data. The image itself may contain sensitive card details, and provider charges may apply.',
              ),
              const SizedBox(height: 10),
              Text(settings.provider.retentionDisclosure),
              const SizedBox(height: 10),
              const Text(
                'Choose Keep offline to continue without sending these '
                'images.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep offline'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Send frames'),
          ),
        ],
      ),
    );
    return approved ?? false;
  }

  Widget _cameraPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize!.height,
          height: controller.value.previewSize!.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Rect _cardFrame(Size screenSize) {
    const cardAspectRatio = 1.586;
    final maxWidth = screenSize.width * (_isPortraitCard ? 0.58 : 0.86);
    final maxHeight = screenSize.height * (_isPortraitCard ? 0.54 : 0.42);
    final desiredHeight = _isPortraitCard
        ? maxWidth * cardAspectRatio
        : maxWidth / cardAspectRatio;
    final height = min(desiredHeight, maxHeight);
    final width = _isPortraitCard
        ? height / cardAspectRatio
        : height * cardAspectRatio;
    return Rect.fromLTWH(
      (screenSize.width - width) / 2,
      (screenSize.height - height) / 2 -
          (_isPortraitCard ? screenSize.height * 0.055 : 0),
      width,
      height,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _withCloseGuard(_buildScanner(context));
  }

  Widget _buildScanner(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.camera_alt_outlined,
                    color: Colors.white,
                    size: 56,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  if (_errorDetails != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(
                        _errorDetails!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.left,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () async {
                      setState(() {
                        _errorMessage = null;
                        _errorDetails = null;
                        _isAiError = false;
                        _isCapturing = false;
                        _isPickingGallery = false;
                        _isProcessing = false;
                        _processingImagePaths = const [];
                        _bestProcessingImagePath = null;
                        _processingUsesAi = false;
                        _processingComplete = false;
                        _galleryStripeFallback = false;
                      });
                      if (_usesNativeScannerOnly) {
                        await _scanWithLocalCardScan(closeOnCancel: true);
                        return;
                      }
                      final controller = _controller;
                      if (controller == null ||
                          !controller.value.isInitialized) {
                        await _initializeCamera();
                      }
                    },
                    child: const Text('Try again'),
                  ),
                  if (_isAiError)
                    TextButton.icon(
                      onPressed: () async {
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AiScanSettingsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Open Smart Scan settings'),
                    ),
                  if (!_usesNativeScannerOnly)
                    TextButton.icon(
                      onPressed: _pickFromGallery,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose another photo'),
                    ),
                  TextButton(
                    onPressed: () => unawaited(_popScanner()),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_isPickingGallery || _isProcessing) {
      return _processingScaffold();
    }

    if (_usesNativeScannerOnly) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  onPressed: () => unawaited(_popScanner()),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 18),
                      Text(
                        _liveQuality.message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  onPressed: () => unawaited(_popScanner()),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 18),
                    Text(
                      'Starting secure camera…',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final size = MediaQuery.sizeOf(context);
    final frame = _cardFrame(size);
    final semantic = AppSemanticColors.of(context);
    final qualityColor = switch (_liveQuality.tone) {
      _ScanQualityTone.neutral => Colors.white,
      _ScanQualityTone.warning => semantic.warning,
      _ScanQualityTone.ready => semantic.success,
    };
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _cameraPreview(),
          CustomPaint(
            painter: CardFramePainter(
              cardFrame: frame,
              frameColor: qualityColor,
            ),
          ),
          Positioned.fill(
            child: Semantics(
              label: 'Camera preview. Tap the card to focus.',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _isCapturing
                    ? null
                    : (details) =>
                          unawaited(_focusAt(details.localPosition, size)),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          if (_focusIndicatorPosition != null)
            Positioned(
              left: _focusIndicatorPosition!.dx - 32,
              top: _focusIndicatorPosition!.dy - 32,
              child: IgnorePointer(
                child: _CameraFocusReticle(settled: _focusIndicatorSettled),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: _isCapturing
                            ? null
                            : () => unawaited(_popScanner()),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.64),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 15,
                              color: Color(0xFF55E59A),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'OFFLINE FIRST · PHOTO DISCARDED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _isCapturing ? null : _toggleFlash,
                        icon: Icon(
                          _isFlashOn ? Icons.flash_on : Icons.flash_off,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                AnimatedContainer(
                  duration: AppMotion.resolve(context, AppMotion.quick),
                  margin: const EdgeInsets.only(bottom: 112),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: qualityColor.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _liveQuality.isReady
                                ? Icons.check_circle
                                : Icons.center_focus_weak,
                            size: 18,
                            color: qualityColor,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                _liveQuality.message,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Live preview frames are checked in memory; only the verified crop is used for local text reading',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 34),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _RoundCameraButton(
                        semanticLabel: 'Choose photo from gallery',
                        onTap: _isCapturing ? null : _pickFromGallery,
                        size: 54,
                        child: const Icon(
                          Icons.photo_library_outlined,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 34),
                      _RoundCameraButton(
                        semanticLabel: _isCapturing
                            ? 'Scanning card'
                            : 'Start scanning card',
                        onTap: _isCapturing
                            ? null
                            : () => _scanWithLocalCardScan(),
                        size: 78,
                        background: Colors.white,
                        child: _isCapturing
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                ),
                              )
                            : Icon(
                                Icons.camera_alt,
                                color: _liveQuality.isReady
                                    ? const Color(0xFF087A49)
                                    : Colors.black87,
                                size: 36,
                              ),
                      ),
                      const SizedBox(width: 34),
                      _RoundCameraButton(
                        semanticLabel: _isPortraitCard
                            ? 'Use horizontal card frame'
                            : 'Use vertical card frame',
                        onTap: _isCapturing
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _isPortraitCard = !_isPortraitCard;
                                });
                              },
                        size: 54,
                        child: Tooltip(
                          message: _isPortraitCard
                              ? 'Use horizontal card frame'
                              : 'Use vertical card frame',
                          child: Icon(
                            _isPortraitCard
                                ? Icons.crop_landscape_outlined
                                : Icons.crop_portrait_outlined,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isCapturing)
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.78),
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.document_scanner_outlined,
                          color: Colors.white,
                          size: 42,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Opening live scanner',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _liveQuality.message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 22),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: const LinearProgressIndicator(
                            minHeight: 7,
                            backgroundColor: Colors.white24,
                            color: Color(0xFF55E59A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _processingScaffold() {
    final choosing = _isPickingGallery && !_isProcessing;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E12),
      body: SafeArea(
        child: Stack(
          children: [
            if (choosing)
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  onPressed: () => unawaited(_popScanner()),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 38),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_processingImagePaths.isNotEmpty) ...[
                      _buildProcessingFrames(),
                      const SizedBox(height: 24),
                    ],
                    Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        color: const Color(0xFF55E59A).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        choosing
                            ? Icons.photo_library_outlined
                            : Icons.document_scanner_outlined,
                        color: const Color(0xFF55E59A),
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 24),
                    AnimatedSwitcher(
                      duration: AppMotion.resolve(context, AppMotion.standard),
                      child: Text(
                        _processingMessage,
                        key: ValueKey(_processingMessage),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    LinearProgressIndicator(
                      value: _processingStep / 3,
                      backgroundColor: Colors.white12,
                      color: Color(0xFF55E59A),
                    ),
                    const SizedBox(height: 12),
                    _buildProcessingStages(),
                    const SizedBox(height: 16),
                    const Text(
                      'Offline is always tried first. Photos are discarded after processing.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingFrames() {
    return SizedBox(
      height: 92,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var index = 0; index < _processingImagePaths.length; index++)
            Padding(
              padding: EdgeInsets.only(
                right: index == _processingImagePaths.length - 1 ? 0 : 8,
              ),
              child: AnimatedContainer(
                duration: AppMotion.resolve(context, AppMotion.quick),
                width: 76,
                height: 92,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        _processingImagePaths[index] == _bestProcessingImagePath
                        ? const Color(0xFF55E59A)
                        : Colors.white24,
                    width: 2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(_processingImagePaths[index]),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Colors.white10,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.72),
                        child: SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                              'Frame ${index + 1}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProcessingStages() {
    final labels = [
      _galleryStripeFallback ? 'Stripe scan' : 'Quality',
      _galleryStripeFallback ? 'Offline fallback' : 'Offline OCR',
      _processingUsesAi ? 'Smart AI' : 'Review',
    ];
    return Row(
      children: [
        for (var index = 0; index < labels.length; index++) ...[
          Expanded(
            child: Column(
              children: [
                Icon(
                  index + 1 < _processingStep ||
                          (_processingComplete && index + 1 == _processingStep)
                      ? Icons.check_circle
                      : index + 1 == _processingStep
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 17,
                  color: index + 1 <= _processingStep
                      ? const Color(0xFF55E59A)
                      : Colors.white30,
                ),
                const SizedBox(height: 3),
                Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: index + 1 <= _processingStep
                        ? Colors.white70
                        : Colors.white30,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (index < labels.length - 1)
            Container(width: 16, height: 1, color: Colors.white24),
        ],
      ],
    );
  }
}

class _LiveScanQuality {
  final String message;
  final bool isReady;
  final _ScanQualityTone tone;

  const _LiveScanQuality({
    required this.message,
    required this.isReady,
    required this.tone,
  });
}

enum _ScanQualityTone { neutral, warning, ready }

class _CameraFocusReticle extends StatelessWidget {
  final bool settled;

  const _CameraFocusReticle({required this.settled});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedContainer(
        duration: AppMotion.resolve(context, AppMotion.quick),
        curve: AppMotion.standardCurve,
        width: settled ? 46 : 64,
        height: settled ? 46 : 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: settled ? const Color(0xFF55E59A) : Colors.white,
            width: 2,
          ),
        ),
        child: Center(
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: settled ? const Color(0xFF55E59A) : Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundCameraButton extends StatelessWidget {
  final VoidCallback? onTap;
  final String semanticLabel;
  final double size;
  final Color? background;
  final Widget child;

  const _RoundCameraButton({
    required this.onTap,
    required this.semanticLabel,
    required this.size,
    required this.child,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      child: AnimatedOpacity(
        duration: AppMotion.resolve(context, AppMotion.quick),
        opacity: onTap == null ? 0.55 : 1,
        child: Material(
          color: background ?? Colors.white.withValues(alpha: 0.18),
          shape: CircleBorder(
            side: BorderSide(color: Colors.white, width: size > 60 ? 4 : 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: size,
              height: size,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class CardFramePainter extends CustomPainter {
  final Rect cardFrame;
  final Color frameColor;

  const CardFramePainter({required this.cardFrame, required this.frameColor});

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()..addRect(Offset.zero & size);
    final card = Path()
      ..addRRect(RRect.fromRectAndRadius(cardFrame, const Radius.circular(16)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, outside, card),
      Paint()..color = Colors.black.withValues(alpha: 0.58),
    );

    final glow = Paint()
      ..color = frameColor.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(cardFrame, const Radius.circular(16)),
      glow,
    );

    final cornerPaint = Paint()
      ..color = frameColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const corner = 30.0;
    _drawCorner(canvas, cardFrame.topLeft, cornerPaint, corner, 1, 1);
    _drawCorner(canvas, cardFrame.topRight, cornerPaint, corner, -1, 1);
    _drawCorner(canvas, cardFrame.bottomLeft, cornerPaint, corner, 1, -1);
    _drawCorner(canvas, cardFrame.bottomRight, cornerPaint, corner, -1, -1);
  }

  void _drawCorner(
    Canvas canvas,
    Offset point,
    Paint paint,
    double length,
    double horizontalDirection,
    double verticalDirection,
  ) {
    canvas.drawLine(
      point,
      point + Offset(length * horizontalDirection, 0),
      paint,
    );
    canvas.drawLine(
      point,
      point + Offset(0, length * verticalDirection),
      paint,
    );
  }

  @override
  bool shouldRepaint(CardFramePainter oldDelegate) {
    return oldDelegate.cardFrame != cardFrame ||
        oldDelegate.frameColor != frameColor;
  }
}

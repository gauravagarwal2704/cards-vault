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
  bool _isAnalyzingFrame = false;
  bool _isPortraitCard = false;
  int _captureProgress = 0;
  int _initializationGeneration = 0;
  String _processingMessage = 'Reading card securely on this device…';
  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);
  String? _errorMessage;
  bool _isAiError = false;
  final OCRService _ocrService = OCRService();
  final AiScanSettingsService _aiSettingsService = AiScanSettingsService();
  final AiCardScanService _aiScanService = AiCardScanService();
  _LiveScanQuality _liveQuality = const _LiveScanQuality(
    message: 'Align the front of your card within the frame',
    isReady: false,
    tone: _ScanQualityTone.neutral,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _initializationGeneration++;
    _controller?.dispose();
    _ocrService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission sheets and the gallery can briefly mark the app inactive.
    // Disposing then races the initial camera permission request and caused the
    // first scanner opening to remain on its loading screen.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _initializationGeneration++;
      _isInitializing = false;
      _controller?.dispose();
      _controller = null;
      _isInitialized = false;
    } else if (state == AppLifecycleState.resumed) {
      final controller = _controller;
      if (!_isPickingGallery &&
          !_isProcessing &&
          (controller == null || !controller.value.isInitialized)) {
        _initializeCamera();
      }
    }
  }

  Future<void> _initializeCamera() async {
    if (_isInitializing || _isPickingGallery || _isProcessing) return;
    final generation = ++_initializationGeneration;
    if (mounted) {
      setState(() {
        _isInitializing = true;
        _errorMessage = null;
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
        // ML Kit downsizes long edges to 2000px, so `high` is faster and avoids
        // the visible shutter pause of an unnecessarily huge capture.
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      _controller = controller;
      await previous?.dispose();
      await controller.initialize().timeout(const Duration(seconds: 12));
      if (!mounted || generation != _initializationGeneration) {
        await controller.dispose();
        return;
      }
      await controller.setFlashMode(FlashMode.off);
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setExposureMode(ExposureMode.auto);
      } catch (_) {
        // Some desktop and older mobile camera implementations do not expose
        // focus/exposure controls.
      }
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isInitializing = false;
          _errorMessage = null;
        });
      }
      // Live quality hints are optional. A slow/unsupported analysis stream
      // must never block the camera from opening or the shutter from working.
      unawaited(_startAnalysisStream(controller, generation));
    } catch (_) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'CardVault could not start the camera. Check camera permission and try again.';
        });
      }
    }
  }

  Future<void> _startAnalysisStream(
    CameraController controller,
    int generation,
  ) async {
    try {
      await controller
          .startImageStream(_analyzeCameraFrame)
          .timeout(const Duration(seconds: 2));
      if (generation != _initializationGeneration &&
          controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Capture remains available without live quality hints.
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

  void _analyzeCameraFrame(CameraImage image) {
    final now = DateTime.now();
    if (_isAnalyzingFrame ||
        _isCapturing ||
        now.difference(_lastAnalysis) < const Duration(milliseconds: 450)) {
      return;
    }
    _isAnalyzingFrame = true;
    _lastAnalysis = now;

    try {
      final quality = _measureLiveQuality(image);
      if (mounted && quality.message != _liveQuality.message) {
        setState(() => _liveQuality = quality);
      }
    } finally {
      _isAnalyzingFrame = false;
    }
  }

  _LiveScanQuality _measureLiveQuality(CameraImage image) {
    if (image.planes.isEmpty || image.width < 8 || image.height < 8) {
      return _liveQuality;
    }

    final step = max(8, min(image.width, image.height) ~/ 70);
    var samples = 0;
    var sum = 0.0;
    var sumSquares = 0.0;
    var glare = 0;
    var edgeSum = 0.0;
    var edgeSamples = 0;

    for (var y = step; y < image.height - step; y += step) {
      for (var x = step; x < image.width - step; x += step) {
        final value = _luminanceAt(image, x, y);
        final right = _luminanceAt(image, x + step, y);
        final bottom = _luminanceAt(image, x, y + step);
        sum += value;
        sumSquares += value * value;
        if (value >= 247) glare++;
        edgeSum += (value - right).abs() + (value - bottom).abs();
        edgeSamples += 2;
        samples++;
      }
    }

    if (samples == 0) return _liveQuality;
    final brightness = sum / samples;
    final contrast = sqrt(
      max(0, sumSquares / samples - brightness * brightness),
    );
    final glareRatio = glare / samples;
    final edgeStrength = edgeSamples == 0 ? 0 : edgeSum / edgeSamples;

    if (brightness < 48) {
      return const _LiveScanQuality(
        message: 'Too dark — add light or turn on flash',
        isReady: false,
        tone: _ScanQualityTone.warning,
      );
    }
    if (brightness > 222 || glareRatio > 0.2) {
      return const _LiveScanQuality(
        message: 'Glare detected — tilt the card slightly',
        isReady: false,
        tone: _ScanQualityTone.warning,
      );
    }
    if (contrast < 18) {
      return const _LiveScanQuality(
        message: 'Use a contrasting background',
        isReady: false,
        tone: _ScanQualityTone.warning,
      );
    }
    if (edgeStrength < 7) {
      return const _LiveScanQuality(
        message: 'Hold steady and let the camera focus',
        isReady: false,
        tone: _ScanQualityTone.warning,
      );
    }
    return const _LiveScanQuality(
      message: 'Ready — hold steady and capture',
      isReady: true,
      tone: _ScanQualityTone.ready,
    );
  }

  int _luminanceAt(CameraImage image, int x, int y) {
    final plane = image.planes.first;
    final rowStride = plane.bytesPerRow;
    final pixelStride = plane.bytesPerPixel ?? 1;
    final offset = y * rowStride + x * pixelStride;
    if (offset < 0 || offset >= plane.bytes.length) return 0;

    if (image.format.group == ImageFormatGroup.bgra8888 &&
        offset + 2 < plane.bytes.length) {
      final blue = plane.bytes[offset];
      final green = plane.bytes[offset + 1];
      final red = plane.bytes[offset + 2];
      return (0.299 * red + 0.587 * green + 0.114 * blue).round();
    }
    return plane.bytes[offset];
  }

  Future<void> _captureImages() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isCapturing) {
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isCapturing = true;
      _captureProgress = 0;
    });
    final capturedPaths = <String>[];
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      try {
        await controller.setFocusPoint(const Offset(0.5, 0.5));
        await controller.setExposurePoint(const Offset(0.5, 0.5));
      } catch (_) {
        // Optional camera capability.
      }

      // Nearby frames reduce single-frame OCR errors from reflections and
      // embossed digits. Three is a useful accuracy/latency balance.
      for (var index = 0; index < 3; index++) {
        if (mounted) setState(() => _captureProgress = index + 1);
        final file = await controller.takePicture();
        capturedPaths.add(file.path);
        if (index < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 110));
        }
      }

      if (!mounted) {
        await CardScanCapture(
          imagePaths: capturedPaths,
          ownsFiles: true,
        ).deleteOwnedFiles();
        return;
      }

      HapticFeedback.selectionClick();
      final capture = CardScanCapture(
        imagePaths: capturedPaths,
        ownsFiles: true,
        crop: _normalizedCardCrop(MediaQuery.sizeOf(context)),
      );
      await _processCapture(capture, fromGallery: false);
    } catch (_) {
      await CardScanCapture(
        imagePaths: capturedPaths,
        ownsFiles: true,
      ).deleteOwnedFiles();
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _captureProgress = 0;
          _errorMessage = 'The capture did not complete. Please try again.';
        });
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isCapturing || _isPickingGallery || _isProcessing) return;
    setState(() {
      _isPickingGallery = true;
      _processingMessage = 'Opening your photo library…';
      _errorMessage = null;
      _isAiError = false;
    });
    try {
      final controller = _controller;
      if (controller != null && controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (!mounted) return;
      if (image == null) {
        setState(() => _isPickingGallery = false);
        final current = _controller;
        if (current == null || !current.value.isInitialized) {
          await _initializeCamera();
        } else {
          unawaited(_startAnalysisStream(current, _initializationGeneration));
        }
        return;
      }
      await _processCapture(
        CardScanCapture(imagePaths: [image.path], ownsFiles: false),
        fromGallery: true,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _isPickingGallery = false;
          _errorMessage = 'The selected photo could not be opened.';
        });
      }
    }
  }

  Future<void> _processCapture(
    CardScanCapture capture, {
    required bool fromGallery,
  }) async {
    if (!mounted) return;
    setState(() {
      _isCapturing = false;
      _isPickingGallery = fromGallery;
      _isProcessing = true;
      _processingMessage = fromGallery
          ? 'Reading the selected photo on this device…'
          : 'Comparing 3 frames on this device…';
    });

    try {
      final ranked = <({String path, ImageQuality quality})>[];
      for (final path in capture.imagePaths) {
        final quality = await ImageUtils.validateImageQuality(
          path,
          crop: capture.crop,
        );
        ranked.add((path: path, quality: quality));
      }
      ranked.sort(
        (a, b) => _qualityScore(b.quality).compareTo(_qualityScore(a.quality)),
      );

      // Quality is advisory. A strict pre-OCR rejection caused valid gallery
      // photos and slightly reflective cards to fail before text recognition.
      final paths = ranked.map((item) => item.path).take(3).toList();
      var result = await _ocrService.processImages(paths, crop: capture.crop);

      if (result.cardNumber == null || result.expiryDate == null) {
        final settings = await _aiSettingsService.load();
        if (mounted && settings.isConfigured) {
          final approved = await _confirmAiUpload(settings);
          if (approved && mounted) {
            setState(() {
              _processingMessage =
                  '${settings.provider.modelLabel} is reading one metadata-free card crop…';
            });
            final outcome = await _aiScanService.scan(
              imagePath: ranked.first.path,
              crop: capture.crop,
              localResult: result,
              settings: settings,
            );
            result = outcome.result;
          }
        }
      }

      if (!mounted) return;
      if (result.cardNumber == null) {
        final bestWarning = ranked.isEmpty
            ? null
            : ranked.first.quality.warning;
        setState(() {
          _isProcessing = false;
          _isPickingGallery = false;
          _errorMessage = bestWarning == null
              ? 'CardVault could not identify the card number. Try another photo or enter it manually.'
              : '$bestWarning CardVault still could not identify the card number.';
        });
        return;
      }

      setState(() => _processingMessage = 'Card found — opening review…');
      HapticFeedback.lightImpact();
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (mounted) Navigator.pop(context, result);
    } on AiCardScanException catch (error) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isPickingGallery = false;
          _isAiError = true;
          _errorMessage = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _isPickingGallery = false;
          _isAiError = false;
          _errorMessage =
              'The card image could not be processed. Try another photo.';
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
                'The offline scan could not confidently read every required field. Send one image directly to ${settings.provider.label} for processing by ${settings.provider.modelLabel}?',
              ),
              const SizedBox(height: 14),
              const Text(
                'CardVault sends:',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                '• One cropped, resized JPEG with metadata removed\n'
                '• A request for card number, expiry, cardholder name, and confidence\n'
                '• Instructions to return null when uncertain and never extract CVV\n'
                '• Your saved key as an HTTPS authentication header to the selected provider',
              ),
              const SizedBox(height: 10),
              const Text(
                'It does not send offline OCR text, other saved cards, or unrelated app data. The image itself may contain sensitive card details, and provider charges may apply.',
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
            child: const Text('Send one image'),
          ),
        ],
      ),
    );
    return approved ?? false;
  }

  NormalizedCardCrop _normalizedCardCrop(Size screenSize) {
    final preview = _controller!.value.previewSize!;
    final sourceWidth = preview.height;
    final sourceHeight = preview.width;
    final scale = max(
      screenSize.width / sourceWidth,
      screenSize.height / sourceHeight,
    );
    final displayedWidth = sourceWidth * scale;
    final displayedHeight = sourceHeight * scale;
    final offsetX = (screenSize.width - displayedWidth) / 2;
    final offsetY = (screenSize.height - displayedHeight) / 2;
    final frame = _cardFrame(screenSize);

    return NormalizedCardCrop(
      left: ((frame.left - offsetX) / displayedWidth).clamp(0, 1),
      top: ((frame.top - offsetY) / displayedHeight).clamp(0, 1),
      width: (frame.width / displayedWidth).clamp(0, 1),
      height: (frame.height / displayedHeight).clamp(0, 1),
    );
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
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () async {
                      setState(() {
                        _errorMessage = null;
                        _isAiError = false;
                        _isCapturing = false;
                        _isPickingGallery = false;
                        _isProcessing = false;
                        _captureProgress = 0;
                      });
                      final controller = _controller;
                      if (controller == null ||
                          !controller.value.isInitialized) {
                        await _initializeCamera();
                      } else if (!controller.value.isStreamingImages) {
                        unawaited(
                          _startAnalysisStream(
                            controller,
                            _initializationGeneration,
                          ),
                        );
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
                  TextButton.icon(
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose another photo'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
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

    if (!_isInitialized || _controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
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
                            : () => Navigator.pop(context),
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
                        'One tap captures 3 quick frames — keep still until ✓',
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
                            ? 'Capturing card'
                            : 'Capture card',
                        onTap: _isCapturing ? null : _captureImages,
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
                                setState(
                                  () => _isPortraitCard = !_isPortraitCard,
                                );
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
                          Icons.pan_tool_alt_outlined,
                          color: Colors.white,
                          size: 42,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Keep still — frame $_captureProgress of 3',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'CardVault compares the frames to reduce glare and OCR mistakes.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 22),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: _captureProgress / 3,
                            minHeight: 7,
                            backgroundColor: Colors.white24,
                            color: const Color(0xFF55E59A),
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
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 38),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    const LinearProgressIndicator(
                      backgroundColor: Colors.white12,
                      color: Color(0xFF55E59A),
                    ),
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

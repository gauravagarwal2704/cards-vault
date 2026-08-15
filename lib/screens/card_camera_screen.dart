import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class CardCameraScreen extends StatefulWidget {
  const CardCameraScreen({super.key});

  @override
  State<CardCameraScreen> createState() => _CardCameraScreenState();
}

class _CardCameraScreenState extends State<CardCameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isFlashOn = false;
  bool _isCapturing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _errorMessage = 'No cameras available';
        });
        return;
      }

      final camera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      await _controller!.setFlashMode(FlashMode.off);
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize camera: $e';
      });
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      if (_isFlashOn) {
        await _controller!.setFlashMode(FlashMode.off);
      } else {
        await _controller!.setFlashMode(FlashMode.torch);
      }
      
      setState(() {
        _isFlashOn = !_isFlashOn;
      });
    } catch (e) {
      // Flash not supported
    }
  }

  Future<void> _captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      final XFile image = await _controller!.takePicture();
      
      final directory = await getTemporaryDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String filePath = path.join(directory.path, 'card_$timestamp.jpg');
      
      await File(image.path).copy(filePath);
      
      if (mounted) {
        Navigator.pop(context, filePath);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to capture image: $e';
        _isCapturing = false;
      });
    }
  }

  /// Picks an existing photo instead of taking one. The caller receives a file
  /// path either way, so it cannot tell a gallery pick from a capture.
  Future<void> _pickFromGallery() async {
    if (_isCapturing) return;

    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (image == null || !mounted) return;

      Navigator.pop(context, image.path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to open gallery: $e';
      });
    }
  }

  Widget _buildGalleryButton() {
    return GestureDetector(
      onTap: _isCapturing ? null : _pickFromGallery,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.2),
          border: Border.all(color: Colors.white70, width: 1.5),
        ),
        child: const Icon(
          Icons.photo_library_outlined,
          color: Colors.white,
          size: 26,
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller!.value.previewSize!.height,
          height: _controller!.value.previewSize!.width,
          child: CameraPreview(_controller!),
        ),
      ),
    );
  }

  Rect _getCardFrameRect(Size screenSize) {
    const double cardAspectRatio = 1.586;
    final double frameWidth = screenSize.width * 0.85;
    final double frameHeight = frameWidth / cardAspectRatio;
    
    final double left = (screenSize.width - frameWidth) / 2;
    final double top = (screenSize.height - frameHeight) / 2;
    
    return Rect.fromLTWH(left, top, frameWidth, frameHeight);
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 64),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    final cardFrame = _getCardFrameRect(size);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraPreview(),
          
          CustomPaint(
            painter: CardFramePainter(cardFrame: cardFrame),
            size: size,
          ),
          
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white, size: 32),
                      ),
                      IconButton(
                        onPressed: _toggleFlash,
                        icon: Icon(
                          _isFlashOn ? Icons.flash_on : Icons.flash_off,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const Spacer(),
                
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 120),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Align card within frame',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                
                Padding(
                  padding: const EdgeInsets.only(bottom: 40.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildGalleryButton(),
                      const SizedBox(width: 32),
                      GestureDetector(
                        onTap: _isCapturing ? null : _captureImage,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(
                              color: Colors.white,
                              width: 4,
                            ),
                          ),
                          child: _isCapturing
                              ? const Padding(
                                  padding: EdgeInsets.all(20.0),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt,
                                  color: Colors.blue,
                                  size: 40,
                                ),
                        ),
                      ),
                      const SizedBox(width: 32),
                      const SizedBox(width: 56),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CardFramePainter extends CustomPainter {
  final Rect cardFrame;

  CardFramePainter({required this.cardFrame});

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()
      ..color = Colors.black.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    final framePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final shadowPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final cardPath = Path()
      ..addRRect(RRect.fromRectAndRadius(cardFrame, const Radius.circular(12)));

    final overlayPath = Path.combine(PathOperation.difference, path, cardPath);
    canvas.drawPath(overlayPath, overlayPaint);

    canvas.drawRRect(
      RRect.fromRectAndRadius(cardFrame, const Radius.circular(12)),
      shadowPaint,
    );
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(cardFrame, const Radius.circular(12)),
      framePaint,
    );

    final cornerLength = 30.0;
    final cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    _drawCorner(canvas, cardFrame.topLeft, cornerLength, cornerPaint, true, true);
    _drawCorner(canvas, cardFrame.topRight, cornerLength, cornerPaint, false, true);
    _drawCorner(canvas, cardFrame.bottomLeft, cornerLength, cornerPaint, true, false);
    _drawCorner(canvas, cardFrame.bottomRight, cornerLength, cornerPaint, false, false);
  }

  void _drawCorner(Canvas canvas, Offset corner, double length, Paint paint, bool isLeft, bool isTop) {
    final horizontalStart = corner;
    final horizontalEnd = Offset(
      isLeft ? corner.dx + length : corner.dx - length,
      corner.dy,
    );
    
    final verticalStart = corner;
    final verticalEnd = Offset(
      corner.dx,
      isTop ? corner.dy + length : corner.dy - length,
    );

    canvas.drawLine(horizontalStart, horizontalEnd, paint);
    canvas.drawLine(verticalStart, verticalEnd, paint);
  }

  @override
  bool shouldRepaint(CardFramePainter oldDelegate) => false;
}


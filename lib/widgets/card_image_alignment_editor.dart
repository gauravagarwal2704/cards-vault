import 'dart:io';

import 'package:flutter/material.dart';

import '../models/card_image_placement.dart';

/// Alignment controls; the card itself is displayed by the main preview.
class CardImageAlignmentEditor extends StatelessWidget {
  const CardImageAlignmentEditor({
    super.key,
    required this.placement,
    required this.onChanged,
  });

  final CardImagePlacement placement;
  final ValueChanged<CardImagePlacement> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Align image', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      const Text(
        'Drag or pinch the main card preview to adjust the image. Use the slider to zoom.',
      ),
      Row(
        children: [
          const Text('Zoom'),
          Expanded(
            child: Slider(
              key: const ValueKey('card-image-zoom'),
              value: placement.zoom.clamp(1.0, 4.0),
              min: 1,
              max: 4,
              label: '${placement.zoom.toStringAsFixed(1)}×',
              onChanged: (zoom) => onChanged(
                CardImagePlacement(zoom: zoom, x: placement.x, y: placement.y),
              ),
            ),
          ),
          Text('${placement.zoom.toStringAsFixed(1)}×'),
          TextButton(
            onPressed: () => onChanged(const CardImagePlacement()),
            child: const Text('Reset'),
          ),
        ],
      ),
    ],
  );
}

/// Drag and pinch editing on the existing live card, without a second preview.
class CardImageAlignmentPreview extends StatefulWidget {
  const CardImageAlignmentPreview({
    super.key,
    required this.path,
    required this.placement,
    required this.onChanged,
    required this.child,
  });

  final String path;
  final CardImagePlacement placement;
  final ValueChanged<CardImagePlacement> onChanged;
  final Widget child;

  @override
  State<CardImageAlignmentPreview> createState() =>
      _CardImageAlignmentPreviewState();
}

class _CardImageAlignmentPreviewState extends State<CardImageAlignmentPreview> {
  ImageStream? _stream;
  Size? _imageSize;
  bool _failed = false;
  Rect? _startRect;
  Offset _startFocal = Offset.zero;
  double _startZoom = 1;
  late final ImageStreamListener _listener = ImageStreamListener(
    (info, _) {
      if (mounted) {
        setState(
          () => _imageSize = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          ),
        );
      }
      info.dispose();
    },
    onError: (_, _) {
      if (mounted) setState(() => _failed = true);
    },
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(CardImageAlignmentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path) {
      _imageSize = null;
      _failed = false;
      _load();
    }
  }

  void _load() {
    _stream?.removeListener(_listener);
    _stream = FileImage(File(widget.path))
        .resolve(createLocalImageConfiguration(context));
    _stream!.addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final placement = widget.placement;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(
          constraints.maxWidth,
          constraints.maxWidth / 1.586,
        );
        return GestureDetector(
          key: const ValueKey('card-image-alignment-preview'),
          behavior: HitTestBehavior.opaque,
          onScaleStart: _imageSize == null
              ? null
              : (details) {
                  _startRect = placement.imageRect(_imageSize!, viewport);
                  _startFocal = details.localFocalPoint;
                  _startZoom = placement.zoom;
                },
          onScaleUpdate: _imageSize == null
              ? null
              : (details) {
                  final startRect = _startRect;
                  if (startRect == null) return;
                  final zoom = (_startZoom * details.scale).clamp(1.0, 4.0);
                  final ratio = zoom / _startZoom;
                  final topLeft =
                      details.localFocalPoint -
                      (_startFocal - startRect.topLeft) * ratio;
                  final rect = Rect.fromLTWH(
                    topLeft.dx,
                    topLeft.dy,
                    startRect.width * ratio,
                    startRect.height * ratio,
                  );
                  widget.onChanged(
                    CardImagePlacement.fromRect(rect, viewport, zoom),
                  );
                },
          child: IgnorePointer(
            child: Stack(
              children: [
                widget.child,
                if (_failed)
                  const Positioned.fill(
                    child: Center(
                      child: Text(
                        'This image is unavailable. Choose another image.',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

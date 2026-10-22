import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Reveals a newly selected background while leaving card details stationary.
class CardBackgroundReveal extends StatefulWidget {
  final Object backgroundKey;
  final Widget child;
  final ImageProvider? imageProvider;

  /// Lower values reveal the background faster. Read again for every reveal.
  final Duration duration;

  const CardBackgroundReveal({
    super.key,
    required this.backgroundKey,
    required this.child,
    this.imageProvider,
    this.duration = const Duration(milliseconds: 400),
  });

  @override
  State<CardBackgroundReveal> createState() => _CardBackgroundRevealState();
}

class _CardBackgroundRevealState extends State<CardBackgroundReveal>
    with SingleTickerProviderStateMixin {
  final _random = math.Random();
  late final AnimationController _controller;
  late Widget _current;
  late Object _currentKey;
  Widget? _previous;
  Offset _origin = Offset.zero;
  bool _targetReady = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _current = widget.child;
    _currentKey = widget.backgroundKey;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1,
    )..addStatusListener(_onAnimationStatus);
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _previous == null) return;
    setState(() {
      _previous = null;
      // Finish the visible circle before revealing the latest queued choice.
      // Intermediate selections are coalesced instead of restarting the reveal.
      if (_targetReady && widget.backgroundKey != _currentKey) {
        _startReveal();
      }
    });
  }

  void _startReveal() {
    _previous = _current;
    _current = widget.child;
    _currentKey = widget.backgroundKey;
    // Avoid extreme corners so random origins have a similar visual pace.
    _origin = Offset(
      0.2 + _random.nextDouble() * 0.6,
      0.2 + _random.nextDouble() * 0.6,
    );
    // Re-read the widget setting so tuning via hot reload takes effect even
    // when this preview's state and controller have been kept alive.
    _controller.duration = widget.duration;
    _controller.forward(from: 0);
  }

  void _applyImmediately() {
    _loadGeneration++;
    _targetReady = true;
    _previous = null;
    _current = widget.child;
    _currentKey = widget.backgroundKey;
    _controller.value = 1;
  }

  void _prepareSelection() {
    final generation = ++_loadGeneration;
    final provider = widget.imageProvider;
    _targetReady = provider == null;
    if (provider == null) {
      if (!_controller.isAnimating) _startReveal();
      return;
    }

    // Decode at the same display size used by the renderer before starting
    // the clock, so the new image cannot pop into a half-finished circle.
    precacheImage(provider, context, onError: (_, _) {}).then((_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _targetReady = true;
        if (!_controller.isAnimating && widget.backgroundKey != _currentKey) {
          _startReveal();
        }
      });
    });
  }

  @override
  void didUpdateWidget(covariant CardBackgroundReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (AppMotion.reduceMotion(context)) {
      _applyImmediately();
    } else if (widget.backgroundKey == _currentKey) {
      // Live field/blur edits do not restart a background transition.
      _current = widget.child;
      _targetReady = true;
      _loadGeneration++;
    } else if (oldWidget.backgroundKey != widget.backgroundKey ||
        oldWidget.imageProvider != widget.imageProvider) {
      _prepareSelection();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduceMotion(context)) _applyImmediately();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_previous == null) return _current;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(child: RepaintBoundary(child: _previous!)),
          ClipPath(
            clipper: _CircleRevealClipper(
              origin: _origin,
              animation: _controller,
            ),
            child: RepaintBoundary(child: _current),
          ),
        ],
      ),
    );
  }
}

class _CircleRevealClipper extends CustomClipper<Path> {
  final Offset origin;
  final Animation<double> animation;

  _CircleRevealClipper({required this.origin, required this.animation})
    : super(reclip: animation);

  @override
  Path getClip(Size size) {
    final center = Offset(origin.dx * size.width, origin.dy * size.height);
    final dx = math.max(center.dx, size.width - center.dx);
    final dy = math.max(center.dy, size.height - center.dy);
    // Add a little initial momentum while retaining the gentle final settle.
    final progress =
        0.7 * Curves.easeInOutSine.transform(animation.value) +
        0.3 * Curves.easeOutSine.transform(animation.value);
    final radius = math.sqrt(dx * dx + dy * dy) * progress;
    return Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  }

  @override
  bool shouldReclip(covariant _CircleRevealClipper oldClipper) =>
      origin != oldClipper.origin || animation != oldClipper.animation;
}

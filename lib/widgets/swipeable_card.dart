import 'package:flutter/material.dart';
import '../theme/app_typography.dart';

class SwipeableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;
  final double cardWidth;
  final double cardHeight;

  const SwipeableCard({
    super.key,
    required this.child,
    this.onShare,
    this.onDelete,
    required this.cardWidth,
    required this.cardHeight,
  });

  @override
  State<SwipeableCard> createState() => _SwipeableCardState();
}

class _SwipeableCardState extends State<SwipeableCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  double _dragOffset = 0.0;
  bool _isDragging = false;
  static const double _maxSwipeOffset = -0.75; // 75% off-screen (25% visible)

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animationController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _isDragging = true;
    _animationController.stop();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    setState(() {
      final delta = details.delta.dx / widget.cardWidth;
      _dragOffset = (_dragOffset + delta).clamp(_maxSwipeOffset, 0.0);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    _isDragging = false;

    final velocity = details.velocity.pixelsPerSecond.dx;
    
    if (_dragOffset < -0.2 || velocity < -500) {
      // Snap to open position
      _animateToOffset(_maxSwipeOffset);
    } else {
      // Snap back to closed position
      _animateToOffset(0.0);
    }
  }

  void _animateToOffset(double target) {
    final start = _dragOffset;
    final end = target;

    _animationController.reset();
    _animationController.forward();

    _animationController.addListener(() {
      setState(() {
        _dragOffset = start + (end - start) * Curves.easeOutCubic.transform(_animationController.value);
      });
    });
  }

  void _closeSwipe() {
    _animateToOffset(0.0);
  }

  void _handleShare() {
    _closeSwipe();
    Future.delayed(const Duration(milliseconds: 300), () {
      widget.onShare?.call();
    });
  }

  void _handleDelete() {
    _closeSwipe();
    Future.delayed(const Duration(milliseconds: 300), () {
      widget.onDelete?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = _dragOffset < -0.1;
    final swipeProgress = (_dragOffset / _maxSwipeOffset).clamp(0.0, 1.0);

    return GestureDetector(
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      onTap: isOpen ? _closeSwipe : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Action buttons (behind the card)
          if (isOpen) _buildActionButtons(swipeProgress),
          
          // Card with transform
          Transform(
            alignment: Alignment.center,
            transform: _buildTransformMatrix(),
            child: widget.child,
          ),
        ],
      ),
    );
  }

  Matrix4 _buildTransformMatrix() {
    final translateX = _dragOffset * widget.cardWidth;
    final rotateY = _dragOffset * 0.4; // Skew effect
    final scale = 1.0 + (_dragOffset * 0.05); // Slight scale down when swiped

    return Matrix4.identity()
      ..setEntry(3, 2, 0.001) // Perspective
      ..translate(translateX, 0.0, 0.0)
      ..rotateY(rotateY)
      ..scale(scale.clamp(0.95, 1.0));
  }

  Widget _buildActionButtons(double progress) {
    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.only(left: widget.cardWidth * 0.3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(width: 20),
            _buildActionButton(
              icon: Icons.share_outlined,
              label: 'Share',
              color: const Color(0xFF0EA5E9),
              onTap: _handleShare,
              progress: progress,
            ),
            const SizedBox(width: 16),
            _buildActionButton(
              icon: Icons.delete_outline,
              label: 'Delete',
              color: const Color(0xFFEF4444),
              onTap: _handleDelete,
              progress: progress,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required double progress,
  }) {
    return Opacity(
      opacity: progress,
      child: Transform.scale(
        scale: 0.8 + (progress * 0.2),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: AppTypography.overline(color: Colors.white).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

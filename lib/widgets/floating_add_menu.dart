import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../theme/app_typography.dart';

enum AddCardOption { nfc, scan, manual }

class FloatingAddMenu extends StatefulWidget {
  final Function(AddCardOption) onOptionSelected;

  const FloatingAddMenu({super.key, required this.onOptionSelected});

  @override
  State<FloatingAddMenu> createState() => _FloatingAddMenuState();
}

class _FloatingAddMenuState extends State<FloatingAddMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotationAnimation;
  late Animation<double> _scaleAnimation;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 0.125,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_isOpen) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    setState(() => _isOpen = !_isOpen);
  }

  void _selectOption(AddCardOption option) {
    _controller.reverse();
    setState(() => _isOpen = false);
    widget.onOptionSelected(option);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final primary = themeProvider.getPrimaryColor();

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        if (_isOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggle,
              child: Container(color: Colors.black26),
            ),
          ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ScaleTransition(
              scale: _scaleAnimation,
              child: FadeTransition(
                opacity: _scaleAnimation,
                child: _buildOptionButton(
                  icon: Icons.edit_outlined,
                  label: 'Add Manually',
                  color: primary,
                  onTap: () => _selectOption(AddCardOption.manual),
                  delay: 0.0,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ScaleTransition(
              scale: _scaleAnimation,
              child: FadeTransition(
                opacity: _scaleAnimation,
                child: _buildOptionButton(
                  icon: Icons.camera_alt_outlined,
                  label: 'Scan Card',
                  color: const Color(0xFF10B981),
                  onTap: () => _selectOption(AddCardOption.scan),
                  delay: 0.1,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ScaleTransition(
              scale: _scaleAnimation,
              child: FadeTransition(
                opacity: _scaleAnimation,
                child: _buildOptionButton(
                  icon: Icons.contactless_outlined,
                  label: 'Add via NFC',
                  color: const Color(0xFF0EA5E9),
                  onTap: () => _selectOption(AddCardOption.nfc),
                  delay: 0.2,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildMainFab(themeProvider),
          ],
        ),
      ],
    );
  }

  Widget _buildMainFab(ThemeProvider themeProvider) {
    final primary = themeProvider.getPrimaryColor();
    final primaryContainer = themeProvider.getPrimaryContainerColor();

    return GestureDetector(
      onTap: _toggle,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primaryContainer, primary],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: RotationTransition(
          turns: _rotationAnimation,
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  Widget _buildOptionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required double delay,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: AppTypography.button(fontSize: 14, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }
}

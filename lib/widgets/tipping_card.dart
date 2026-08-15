import 'package:flutter/material.dart';
import '../theme/app_typography.dart';

class TippingCard extends StatelessWidget {
  final int index;
  final String title;
  final String subtitle;
  final Color backgroundColor;
  final double cardHeight;

  const TippingCard({
    super.key,
    required this.index,
    required this.title,
    required this.subtitle,
    required this.backgroundColor,
    this.cardHeight = 200,
  });

  static const List<Color> cardColors = [
    Color(0xFFD4D4D4), // Silver/Gray - Credit Card
    Color(0xFF8BC34A), // Light Green - Crypto Card
    Color(0xFFFFF59D), // Yellow - Debit Card
    Color(0xFFE8DCC8), // Beige/Khaki - Internet Card
    Color(0xFFFFCDD2), // Light Pink - Bonus Card
    Color(0xFF9E9E9E), // Dark Gray - Amex style
    Color(0xFFE57373), // Red - Premium Card
    Color(0xFFBA68C8), // Purple - Savings Card
    Color(0xFFCE93D8), // Lavender - Rewards Card
    Color(0xFF81D4FA), // Light Blue - Travel Card
    Color(0xFFA5D6A7), // Mint Green - Eco Card
    Color(0xFFFFCC80), // Orange - Business Card
  ];

  static Color getColorForIndex(int index) {
    return cardColors[index % cardColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final indexString = (index + 1).toString().padLeft(2, '0');

    return Container(
      height: cardHeight,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withOpacity(0.35),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 20,
            top: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.display(fontSize: 26, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTypography.subtitle(
                    color: Colors.white.withOpacity(0.75),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            bottom: -10,
            child: Text(
              indexString,
              style: AppTypography.display(
                fontSize: cardHeight * 0.55,
                color: Colors.white.withOpacity(0.25),
              ).copyWith(
                fontWeight: FontWeight.w800,
                height: 1.0,
                letterSpacing: -2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

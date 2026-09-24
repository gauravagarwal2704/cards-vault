import 'package:flutter/material.dart';

/// Keeps wallet-card text styling intact while a [Hero] is in the Navigator
/// overlay. Without a Material ancestor, MaterialApp's fallback text style
/// adds a yellow double underline to partially-specified card text styles.
class WalletCardHero extends StatelessWidget {
  final Object tag;
  final Widget child;

  const WalletCardHero({super.key, required this.tag, required this.child});

  @override
  Widget build(BuildContext context) {
    final flightTextStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(decoration: TextDecoration.none);

    return Hero(
      tag: tag,
      child: Material(
        type: MaterialType.transparency,
        textStyle: flightTextStyle,
        child: child,
      ),
    );
  }
}

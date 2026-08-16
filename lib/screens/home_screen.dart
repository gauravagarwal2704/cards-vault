import 'package:flutter/material.dart';

import 'saved_cards_screen.dart';

/// Backwards-compatible route kept for older deep links.
///
/// The wallet is now the canonical home experience, so this route deliberately
/// shares the same Material 3 screen instead of maintaining a second menu UI.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const SavedCardsScreen();
}

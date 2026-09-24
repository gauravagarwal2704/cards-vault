import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy Dart routes and replaced add menu stay removed', () {
    for (final path in const [
      'lib/screens/add_card_screen.dart',
      'lib/screens/home_screen.dart',
      'lib/widgets/floating_add_menu.dart',
      'lib/widgets/tipping_card.dart',
    ]) {
      expect(File(path).existsSync(), isFalse, reason: path);
    }

    final walletSource = File('lib/screens/saved_cards_screen.dart')
        .readAsStringSync();
    expect(walletSource, contains('enum _AddCardOption'));
    expect(walletSource, isNot(contains('FloatingAddMenu')));
    expect(
      walletSource,
      isNot(contains("import '../widgets/floating_add_menu.dart'")),
    );
  });
}

import 'package:cards_wallet/screens/privacy_policy_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('privacy policy describes local data handling and deletion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const PrivacyPolicyScreen(),
      ),
    );

    expect(find.text('CardVault Privacy Policy'), findsOneWidget);
    expect(find.text('Data you choose to store'), findsOneWidget);
    expect(find.text('Camera, photos, and NFC'), findsOneWidget);
    expect(find.text('Retention and deletion'), findsOneWidget);
    expect(find.textContaining('SmartAI'), findsNothing);
    expect(
      find.byKey(const ValueKey('published-privacy-policy-link')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('privacy-contact-link')), findsOneWidget);
  });
}

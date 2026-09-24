import 'package:cards_wallet/providers/theme_provider.dart';
import 'package:cards_wallet/widgets/group_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('group names are collected in a bottom sheet', (tester) async {
    String? result;

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showGroupNameSheet(
                    context,
                    title: 'New Group',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('New Group'), findsOneWidget);
    expect(find.byKey(const ValueKey('group-name-field')), findsOneWidget);

    final saveButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('save-group-name')),
    );
    expect(saveButton.onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('group-name-field')),
      'Airport lounge',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-group-name')));
    await tester.pumpAndSettle();

    expect(result, 'Airport lounge');
    expect(find.byType(BottomSheet), findsNothing);
  });
}

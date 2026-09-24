import 'package:cards_wallet/services/backup_crypto.dart';
import 'package:cards_wallet/widgets/backup_password_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('new backup passwords require the strengthened minimum', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BackupPasswordDialog(
            title: 'Export backup',
            confirmLabel: 'Export',
            requireConfirm: true,
          ),
        ),
      ),
    );

    expect(
      find.text(
        'Use $backupMinimumPasswordLength or more characters. This password cannot be recovered.',
      ),
      findsOneWidget,
    );

    final fields = find.byType(TextFormField);
    final shortPassword = List.filled(
      backupMinimumPasswordLength - 1,
      'x',
    ).join();
    await tester.enterText(fields.at(0), shortPassword);
    await tester.enterText(fields.at(1), shortPassword);
    await tester.tap(find.text('Export'));
    await tester.pump();

    expect(
      find.text('At least $backupMinimumPasswordLength characters'),
      findsOneWidget,
    );
  });
}

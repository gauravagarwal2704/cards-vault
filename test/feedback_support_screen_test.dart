import 'package:cards_wallet/providers/theme_provider.dart';
import 'package:cards_wallet/screens/feedback_support_screen.dart';
import 'package:cards_wallet/services/support_email_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'feedback form sends category, comments, and diagnostics choice',
    (tester) async {
      SupportFeedbackType? sentType;
      String? sentComments;
      bool? sentDiagnostics;
      var downloadCount = 0;

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
          child: MaterialApp(
            home: FeedbackSupportScreen(
              sendFeedback: (type, comments, includeDiagnostics) async {
                sentType = type;
                sentComments = comments;
                sentDiagnostics = includeDiagnostics;
              },
              downloadLogs: () async {
                downloadCount++;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sendButton = find.byKey(const ValueKey('send-feedback-button'));
      expect(tester.widget<FilledButton>(sendButton).onPressed, isNull);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('attach-diagnostics-checkbox')),
            )
            .value,
        isTrue,
      );

      await tester.tap(find.byKey(const ValueKey('feedback-type-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Feature Request').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('feedback-comments-field')),
        'Please add card reminders.',
      );
      await tester.pump();
      await tester.ensureVisible(sendButton);
      await tester.pumpAndSettle();
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      expect(sentType, SupportFeedbackType.featureRequest);
      expect(sentComments, 'Please add card reminders.');
      expect(sentDiagnostics, isTrue);
      expect(find.text('Email draft opened'), findsOneWidget);
      ScaffoldMessenger.of(
        tester.element(sendButton),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();

      final downloadButton = find.byKey(
        const ValueKey('download-diagnostic-logs-button'),
      );
      await tester.ensureVisible(downloadButton);
      await tester.pumpAndSettle();
      await tester.tap(downloadButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(downloadCount, 1);
      expect(find.text('Diagnostic logs saved'), findsOneWidget);
    },
  );
}

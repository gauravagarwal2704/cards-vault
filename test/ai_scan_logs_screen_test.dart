import 'package:cards_wallet/providers/theme_provider.dart';
import 'package:cards_wallet/screens/ai_scan_logs_screen.dart';
import 'package:cards_wallet/services/ai_scan_log_service.dart';
import 'package:cards_wallet/services/ai_scan_settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('scan log expands inline instead of opening a modal', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final entry = AiScanLogEntry(
      id: 'inline-log',
      createdAt: DateTime(2026, 8, 17, 12, 30),
      provider: AiScanProvider.openAi,
      model: 'Vision model',
      endpoint: 'https://api.example.test/scan',
      httpStatus: 503,
      succeeded: false,
      message: 'Provider unavailable',
      requestSummary: 'Three sanitized frames',
      requestBody: '{"request":"redacted"}',
      responseBody: '{"error":"unavailable"}',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: AiScanLogsScreen(logLoader: () async => [entry]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Provider response'), findsNothing);
    await tester.tap(find.textContaining('OpenAI · HTTP 503'));
    await tester.pumpAndSettle();

    expect(find.text('Provider response'), findsOneWidget);
    expect(find.text(AiScanLogEntry.redactedResponseBody), findsOneWidget);
    expect(find.textContaining('unavailable'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });
}

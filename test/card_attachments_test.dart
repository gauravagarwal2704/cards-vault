import 'package:cards_wallet/providers/theme_provider.dart';
import 'package:cards_wallet/widgets/card_attachments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('attachment loading waits for the route transition', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final themeProvider = ThemeProvider();
    addTearDown(themeProvider.dispose);

    Widget buildGallery(double animationValue) {
      return ChangeNotifierProvider.value(
        value: themeProvider,
        child: MaterialApp(
          theme: themeProvider.lightTheme,
          home: Scaffold(
            body: CardAttachmentsGallery(
              cardId: 'card-id',
              attachmentIds: const ['attachment-id'],
              loadAnimation: animationValue == 1
                  ? kAlwaysCompleteAnimation
                  : const AlwaysStoppedAnimation(0.5),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildGallery(0.5));

    expect(
      find.byKey(const ValueKey('card-attachments-deferred')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('card-attachments-gallery')),
      findsNothing,
    );

    await tester.pumpWidget(buildGallery(1));

    expect(
      find.byKey(const ValueKey('card-attachments-deferred')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('card-attachments-gallery')),
      findsOneWidget,
    );
  });

  testWidgets('photo viewer starts fitted and permits zooming out', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ZoomablePhoto(
            child: ColoredBox(color: Colors.blue, child: SizedBox.expand()),
          ),
        ),
      ),
    );

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.minScale, 0.5);
    expect(viewer.maxScale, 5);
    expect(viewer.boundaryMargin, const EdgeInsets.all(80));
  });
}
